pragma Singleton
import Quickshell
import Quickshell.Services.Polkit
import QtQuick

// ==========================================================================
// PolkitService.qml — автентифікація (polkit) у самому шелі.
//
// polkitd (системний демон) не показує діалогів сам — він питає агента в
// сеансі користувача. Раніше в Edots агента не було зовсім: pkexec, зміна
// системних налаштувань, монтування дисків і т.п. або падали, або чекали
// пароля в терміналі. Тепер агентом є Quickshell, а UI — PolkitDialog.
//
// Потік запиту (один за раз):
//   active → flow.message / actionId / identities
//   flow.isResponseRequired → користувач вводить пароль → flow.submit()
//   flow.authenticationSucceeded / authenticationFailed / cancelled → закрити
//
// Сам агент реєструється в polkitd при старті шела. Пароль ніде не
// зберігається: він іде прямо в PAM-сесію всередині polkit.
// ==========================================================================
Singleton {
    id: root

    readonly property bool registered: agent.isRegistered
    readonly property bool active: agent.isActive
    readonly property var flow: agent.flow

    // ── те, що показує діалог (з захистом від null) ──
    readonly property string message: root.active && root.flow ? (root.flow.message || "") : ""
    readonly property string actionId: root.active && root.flow ? (root.flow.actionId || "") : ""
    readonly property string iconName: root.active && root.flow ? (root.flow.iconName || "") : ""
    readonly property string prompt: root.active && root.flow ? (root.flow.inputPrompt || "") : ""
    readonly property string note: root.active && root.flow ? (root.flow.supplementaryMessage || "") : ""
    readonly property bool noteError: root.active && root.flow ? root.flow.supplementaryIsError === true : false
    readonly property bool needInput: root.active && root.flow ? root.flow.isResponseRequired === true : false
    readonly property bool responseVisible: root.active && root.flow ? root.flow.responseVisible === true : false
    readonly property bool failed: root.active && root.flow ? root.flow.failed === true : false
    readonly property var identities: root.active && root.flow ? root.flow.identities : []

    function submit(value) {
        if (root.active && root.flow) root.flow.submit(value)
    }
    function cancel() {
        if (root.active && root.flow) root.flow.cancelAuthenticationRequest()
    }
    function selectIdentity(id) {
        if (root.active && root.flow && id) root.flow.selectedIdentity = id
    }
    function identityLabel(id) {
        if (!id) return ""
        return id.displayName && id.displayName.length > 0 ? id.displayName
            : (id.string && String(id.string).length > 0 ? String(id.string) : "")
    }

    PolkitAgent {
        id: agent
        path: "/org/quickshell/EdotsPolkit"
    }
}
