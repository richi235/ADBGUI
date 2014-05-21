qx.Class.define("myproject.myScroll", {
   extend : qx.ui.container.Scroll,
   events : {
      "addobject" : "qx.event.type.Data",
      "delobject" : "qx.event.type.Data",
      "unlock"    : "qx.event.type.Data"
   }
});
