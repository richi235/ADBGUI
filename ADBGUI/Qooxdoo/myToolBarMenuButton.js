qx.Class.define("myproject.myToolBarMenuButton", {
   extend : qx.ui.toolbar.MenuButton,
   events : {
      "addobject" : "qx.event.type.Data",
      "delobject" : "qx.event.type.Data"
   }
});
