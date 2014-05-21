qx.Class.define("myproject.myToolBarButton", {
   extend : qx.ui.toolbar.Button,
   events : {
      "addobject" : "qx.event.type.Data",
      "delobject" : "qx.event.type.Data"
   }
});
