require('dotenv').config();
const fs = require('fs');
const path = require('path');
const mqttClient = require('../../mqtt-client');


// Função para criar um novo usuário
async function createUser(userData) {
    try {
        // === VALIDAÇÕES CONFORME NORMA ABNT NBR 25608 ===
        
        // Validação de campos obrigatórios
        if (!userData.name || userData.name.trim() === '') {
            throw new Error('Nome (nickname) é obrigatório');
        }
        
        if (userData.name.trim().length > 20) {
            throw new Error('Nome deve ter no máximo 20 caracteres');
        }

        // Validação condicional: maxContentRating obrigatório se parentalControl = true
        if (userData.parentalControl && !userData.maxContentRating) {
            throw new Error('maxContentRating é obrigatório quando controle parental está ativo');
        }

        // Validação da classificação de conteúdo
        if (userData.maxContentRating && !validateContentRating(userData.maxContentRating)) {
            throw new Error('maxContentRating deve ser um dos valores: L, 10, 12, 14, 16, 18');
        }

        // Validação da largura da janela de libras
        if (userData.closedSigningWidth && !validateSigningWidth(userData.closedSigningWidth)) {
            throw new Error('closedSigningWidth deve estar entre 14 e 28');
        }

        // Validação do lado da janela de libras
        if (userData.closedSigningSide && !['left', 'right'].includes(userData.closedSigningSide)) {
            throw new Error('closedSigningSide deve ser "left" ou "right"');
        }

        // Gerar ID único
        const userId = generateUserId();

        // Criar objeto do usuário conforme norma ABNT NBR 25608
        const newUser = {
            // === CAMPOS OBRIGATÓRIOS DA NORMA ===
            id: userId,                                                    // UUID string
            nickname: userData.name.trim(),                                // String (até 20 chars)
            parentalControl: userData.parentalControl || false,            // Boolean
            closedCaptioning: userData.captions || userData.closedCaptioning || false,    // Boolean
            closedSigning: userData.signLanguageWindow || userData.closedSigning || false, // Boolean
            closedSigningSide: userData.closedSigningSide || 'right',      // Enum: left|right
            closedSigningWidth: validateSigningWidth(userData.closedSigningWidth) ? 
                               userData.closedSigningWidth : 20,           // Integer 14-28
            audioDescription: userData.audioDescription || false,          // Boolean
            dialogEnhancement: userData.dialogueEnhancement || userData.dialogEnhancement || false, // Boolean
            voiceGuidance: userData.voiceGuidance || false,               // Boolean
            
            // === CAMPOS CONDICIONAIS ===
            maxContentRating: userData.parentalControl ? 
                            (userData.maxContentRating || userData.ageRating || 'L') : null, // String (se parentalControl = true)
            
            // === CAMPOS OPCIONAIS DA NORMA ===
            avatar: userData.avatar || getDefaultAvatar(),                 // File path
            audioLanguage: userData.language || userData.audioLanguage || 'pt-br',           // String
            closeCaptioningLanguage: userData.closeCaptioningLanguage || 
                                   userData.language || userData.audioLanguage || 'pt-br',   // String  
            userInterfaceLanguage: userData.userInterfaceLanguage || 
                                 userData.language || userData.audioLanguage || 'pt-br',     // String
            
            // === CAMPOS PARA COMPATIBILIDADE (mantidos) ===
            name: userData.name.trim(),                                    // Compatibilidade interna
            isGroup: userData.isGroup || false,                           // Compatibilidade
            language: userData.language || userData.audioLanguage || 'pt-br', // Compatibilidade
            captions: userData.captions || userData.closedCaptioning || false, // Compatibilidade
            subtitle: userData.captions || userData.closedCaptioning || userData.subtitle || false, // Compatibilidade
            signLanguageWindow: userData.signLanguageWindow || userData.closedSigning || false, // Compatibilidade
            dialogueEnhancement: userData.dialogueEnhancement || userData.dialogEnhancement || false, // Compatibilidade
            
            // === CAMPOS LEGADOS (mantidos) ===
            gender: userData.gender || null,
            ageRating: userData.ageRating || userData.maxContentRating || null,
            age: userData.age || null,
            accessConsent: userData.accessConsent || []
        };

        // Ler o arquivo userData.json atual
        const userDataPath = path.join(process.env.USER_DATA_PATH, 'userData.json');
        let currentData = JSON.parse(fs.readFileSync(userDataPath, 'utf8'));
        
        // Adicionar o novo usuário
        currentData.users.push(newUser);
        
        // Salvar de volta no arquivo
        fs.writeFileSync(userDataPath, JSON.stringify(currentData, null, '\t'));
        
        // Atualizar DATA local
        DATA.users.push({
            id: newUser.id,
            name: newUser.name,
            avatar: newUser.avatar
        });
        
        // Notificar via MQTT
        mqttClient.publish(mqttClient.TOPIC.users, process.env.USER_DATA_PATH);
        
        return newUser;
        
    } catch (error) {
        throw new Error(`Erro ao criar usuário: ${error.message}`);
    }
}

// Função para gerar ID único (similar ao Profile Creation)
function generateUserId() {
    return `user_${Date.now()}`;
}

// Função para obter um avatar padrão válido
function getDefaultAvatar() {
    // Avatares disponíveis: 0.png, 1.png, 2.png
    const availableAvatars = ['0.png', '1.png', '2.png'];
    const randomIndex = Math.floor(Math.random() * availableAvatars.length);
    return availableAvatars[randomIndex];
}

// Função para validar largura da janela de libras (norma ABNT NBR 25608)
function validateSigningWidth(width) {
    if (!width) return false;
    const numWidth = parseInt(width);
    return numWidth >= 14 && numWidth <= 28;
}

// Função para validar classificação de conteúdo
function validateContentRating(rating) {
    const validRatings = ['L', '10', '12', '14', '16', '18'];
    return validRatings.includes(rating);
}

module.exports = {
    content,
	script,
    createUser
}