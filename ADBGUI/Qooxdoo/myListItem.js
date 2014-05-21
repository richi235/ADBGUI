qx.Class.define("myproject.myListItem", {
   extend : qx.ui.form.ListItem,
   events : {
      "addobject" : "qx.event.type.Data",
      "delobject" : "qx.event.type.Data"
   }
});
