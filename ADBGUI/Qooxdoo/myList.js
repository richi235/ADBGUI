qx.Class.define("myproject.myList", {
   extend : qx.ui.form.List,
   events : {
      "addobject" : "qx.event.type.Data",
      "delobject" : "qx.event.type.Data",
      "reloadData" : "qx.event.type.Data"
   }
});
