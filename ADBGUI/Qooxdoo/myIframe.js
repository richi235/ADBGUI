qx.Class.define("myproject.myIframe", {
   extend : qx.ui.embed.ThemedIframe,
   events : {
      "addobject" : "qx.event.type.Data",
      "delobject" : "qx.event.type.Data"
   }
});
