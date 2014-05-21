qx.Class.define("myproject.myTextArea", {
   extend : qx.ui.form.TextArea,
   events : {
      "addobject" : "qx.event.type.Data",
      "delobject" : "qx.event.type.Data",
      "unlock"    : "qx.event.type.Data"
   }
});
