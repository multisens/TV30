package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net/http"
	"time"
)

const pluginName = "consent-validator"

var HandlerRegisterer = registerer(pluginName)

type registerer string

func (r registerer) RegisterHandlers(f func(
	name string,
	handler func(context.Context, map[string]interface{}, http.Handler) (http.Handler, error),
)) {
	f(string(r), r.registerHandlers)
}

var httpClient = &http.Client{
	Timeout: 5 * time.Second,
	Transport: &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	},
}

func (r registerer) registerHandlers(
	_ context.Context,
	extra map[string]interface{},
	next http.Handler,
) (http.Handler, error) {
	config, ok := extra[string(r)].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("[%s] configuração ausente no krakend.json", pluginName)
	}

	ccwsURL, ok := config["ccws_url"].(string)
	if !ok || ccwsURL == "" {
		return nil, fmt.Errorf("[%s] ccws_url não configurado", pluginName)
	}

	fmt.Printf("[%s] plugin registrado — ccws: %s\n", pluginName, ccwsURL)

	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		// Monta URL do CCWS com o path original da requisição
		targetURL := ccwsURL + req.URL.RequestURI()

		ccwsReq, err := http.NewRequestWithContext(req.Context(), req.Method, targetURL, req.Body)
		if err != nil {
			http.Error(w, `{"error":"consent-validator: erro interno"}`, http.StatusInternalServerError)
			return
		}

		for key, vals := range req.Header {
			for _, v := range vals {
				ccwsReq.Header.Add(key, v)
			}
		}

		resp, err := httpClient.Do(ccwsReq)
		if err != nil {
			fmt.Printf("[%s] CCWS indisponível: %v\n", pluginName, err)
			http.Error(w, `{"error":"CCWS indisponível"}`, http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()

		// Repassa a resposta do CCWS diretamente ao cliente
		body, _ := io.ReadAll(resp.Body)
		for key, vals := range resp.Header {
			for _, v := range vals {
				w.Header().Add(key, v)
			}
		}
		w.WriteHeader(resp.StatusCode)
		w.Write(body)
	}), nil
}

func main() {}
