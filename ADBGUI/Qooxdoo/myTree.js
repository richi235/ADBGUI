qx.Class.define("myproject.myTree", {
   extend : qx.ui.tree.Tree,
   events : {
      "addobject" : "qx.event.type.Data",
      "delobject" : "qx.event.type.Data"
   }
});
