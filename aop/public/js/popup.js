let has_popup = false;
let yesno_popup = false;

function presentPopup(type, content, timeout) {
    console.log(`Pediu popup ${type}, com ${content}, por ${timeout}`);
    has_popup = true;

    if (type == 'yesno') {
        yesno_popup = true;
        $('#popup').html(`<span class="text">${content}</span>\n` +
                        '<div class="buttons">\n' +
                            '<div id="btyes" class="button focused" moveleft="btno" moveright="btno" select="PopupYes">Sim</div>\n' +
                            '<div id="btno" class="button" moveleft="btyes" moveright="btyes" select="PopupNo">Não</div>\n' +
                        '</div>');
        $('#popup').height('25%');

        const timeoutid = setTimeout(() => {
            if (has_popup) {
                yesno_popup = false;
                ClosePopup();
                publishTopic('aop/display/layers/popup/yesno/response', 'false');
            }
        }, timeout);

        window.PopupYes = () => {
            ClosePopup();
            publishTopic('aop/display/layers/popup/yesno/response', 'true');
            clearTimeout(timeoutid);
        }

        window.PopupNo = () => {
            ClosePopup();
            publishTopic('aop/display/layers/popup/yesno/response', 'false');
            clearTimeout(timeoutid);
        }
    }
    else {
        if (type == 'pin') {
            $('#popup').html('<span class="text">Digite o pin a seguir no seu dispositivo.</span>\n' +
                            `<span class="pin">${content}</span>`);
            $('#popup').height('25%');
        }
        else if (type == 'qrcode') {
            $('#popup').html('<span class="text">Escaneie o QR code abaixo com seu dispositivo.</span>\n' +
                            `<div id="qrcode"></div>`);
            new QRCode(document.getElementById('qrcode'), {
                text: content,
                width: 128,
                height: 128,
                colorDark: "rgb(40, 40, 40)",
                colorLight: "rgb(200, 200, 200)",
            });
            $('#popup').height('40%');
        }

        setTimeout(() => {
            if (has_popup) {
                ClosePopup();
            }
        }, timeout);
    }
    $('#popup').show();
}

function ClosePopup() {
    has_popup = false;
    $('#popup').hide();
    $('#popup').html('');
    window.PopupYes = null;
    window.PopupNo = null;
}