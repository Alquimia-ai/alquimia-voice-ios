import Foundation

/// UI copy, centralized. Spanish for the proof of concept.
enum L10n {
    enum App {
        static let eyebrow = "Alquimia · Voice"
        static let newConversation = "Nueva conversación"
        static let session = "Sesión"
        static let settings = "Ajustes"
        static let reconnect = "Reconectar"
    }

    enum Phase {
        static let idle = "Inactivo"
        static let connecting = "Conectando"
        static let listening = "En escucha"
        static let userSpeaking = "Te escucho"
        static let recording = "Grabando"
        static let thinking = "Pensando"
        static let speaking = "Hablando"
        static let ended = "Finalizada"
    }

    enum Actions {
        static let startCall = "Iniciar conversación"
        static let endCall = "Terminar"
        static let holdToTalk = "Mantener para hablar"
        static let mute = "Silenciar"
        static let unmute = "Activar micrófono"
        static let testConnection = "Probar conexión"
        static let done = "Listo"
        static let show = "Mostrar"
        static let hide = "Ocultar"
    }

    enum Hints {
        static let noReply = "El agente no respondió. Seguimos escuchando."
        static let noReplyPTT = "El agente no respondió. Probá de nuevo."
        static let notHeard = "No te escuché. Mantené presionado y hablá un poco más."
        static let holdToTalk = "Mantené presionado el botón mientras hablás."
        static let waitingReply = "Esperando la respuesta del agente…"
        static let closedWithCode = "Conexión cerrada (código %d)."
        static let muted = "Micrófono silenciado."
    }

    enum Ended {
        static let user = "Conversación terminada."
        static let background = "La conversación se cerró al pasar a segundo plano."
        static let interrupted = "La conversación se cerró por una interrupción de audio."
        static let remote = "El servidor cerró la conexión"
        static let error = "Error"
    }

    enum Transcript {
        static let emptyEyebrow = "Sin mensajes"
        static let emptyBody = "La transcripción de cada turno aparece acá cuando el agente termina de hablar."
        static let you = "Vos"
        static let agent = "Agente"
        static let loading = "Actualizando…"
    }

    enum Settings {
        static let title = "Configuración"
        static let runtimeSection = "Runtime"
        static let runtimeURL = "URL del runtime"
        static let runtimePlaceholder = "https://runtime.ejemplo.com"
        static let token = "Token (Bearer)"
        static let tokenPlaceholder = "API token o JWT"
        static let agentSection = "Agente"
        static let assistantID = "Assistant ID"
        static let assistantPlaceholder = "mi-agente o espacio/agente:0.0.1"
        static let agentspaceID = "Agentspace"
        static let channelID = "Channel ID"
        static let voiceSection = "Voz"
        static let mode = "Modo"
        static let handsFree = "Manos libres"
        static let pushToTalk = "Mantener para hablar"
        static let localBargeIn = "Cortar la reproducción al hablar"
        static let localBargeInHelp = "Si el agente está hablando y vos empezás a hablar, la app corta la reproducción local. El servidor no soporta interrupciones todavía."
        static let debugSection = "Detección local de voz"
        static let activation = "Umbral de activación"
        static let activationHelp = "El servidor usa −40 dBFS. Este valor solo afecta el estado “Pensando” en pantalla."
        static let invalidURL = "Ingresá una URL http:// o https:// válida."
        static let missingToken = "Falta el token."
        static let missingAssistant = "Falta el assistant id."
        static let testing = "Probando…"
        static let testOK = "Conexión y token válidos."
        static let testFailed = "Falló la prueba: %@"
    }

    enum Errors {
        static let invalidURL = "La URL del runtime no es válida."
        static let unauthorized = "El runtime rechazó el token (HTTP %d)."
        static let handshake = "No se pudo abrir el WebSocket%@."
        static let transport = "Se perdió la conexión: %@"
        static let notConnected = "No hay conexión activa."
        static let microphoneDenied = "Sin permiso de micrófono. Habilitalo en Ajustes del sistema."
        static let noInput = "No hay entrada de audio disponible."
        static let converter = "No se pudo preparar el conversor de audio."
        static let engineStart = "No se pudo iniciar el motor de audio: %@"
        static let mediaReset = "El sistema de audio se reinició."
        static let badResponse = "Respuesta inválida del runtime."
        static let http = "El runtime respondió HTTP %d."
    }
}
