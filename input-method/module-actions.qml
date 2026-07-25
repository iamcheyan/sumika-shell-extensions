import QtQuick

import qs.modules.inputmethod as InputMethodMod
import qs.core.runtime
///
/// Registers QML-callback actions for cycling the input method schema
/// via the InputMethod service. Loaded by ModuleActionHost when the
/// input-method module is enabled.
Item {
    Component.onCompleted: {
        var im = InputMethodMod.InputMethod
        ActionManager.register("input-method.cycle", "inputmethod", "Cycle input method schema", {
            type: "qml",
            call: function(p) {
                var dir = 1
                if (typeof p === "number") dir = p
                else if (typeof p === "string") {
                    var n = parseInt(p, 10)
                    if (!isNaN(n)) dir = n
                }
                else if (p && p.direction !== undefined) dir = p.direction
                im.cycleSchema(dir)
            }
        }, {description: "Switch to the next or previous input method schema",
            paramsSchema: {type: "object", properties: {direction: {type: "integer"}}}})
    }
}
