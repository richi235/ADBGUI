qx.Class.define("myproject.myToolBar", {
   extend : qx.ui.toolbar.ToolBar,
   events : {
      "addobject" : "qx.event.type.Data",
      "delobject" : "qx.event.type.Data"
   }
});
