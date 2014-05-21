qx.Class.define("myproject.myTable", {
   extend : qx.ui.table.Table,
   events : {
      "addobject" : "qx.event.type.Data",
      "delobject" : "qx.event.type.Data",
      "reloadData" : "qx.event.type.Data"
   }
});
