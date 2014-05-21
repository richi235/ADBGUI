/* ************************************************************************

   qooxdoo - the new era of web development

   http://qooxdoo.org

   Copyright:
     2004-2010 1&1 Internet AG, Germany, http://www.1und1.de

   License:
     LGPL: http://www.gnu.org/licenses/lgpl.html
     EPL: http://www.eclipse.org/org/documents/epl-v10.php
     See the LICENSE file in the project's top-level directory for details.

   Authors:
     * Tobias Oetiker

************************************************************************ */

qx.Class.define('myproject.myRemoteTableModel', {

  extend : qx.ui.table.model.Remote,

  /* construct : function() {
    this.base(arguments);
    this.debug("Xoah.");
    this.setColumns(["Id","Text"],["id","text"]);
  }, */

  members : {

     // overloaded - called whenever the table requests the row count
    _loadRowCount : function() {
      this.main.sendRequest("job=getrowcount,oid=" + this.id  + ",table=" + this.curtabletablename + this.urlappend);
    },

    _loadRowData : function(firstRow, lastRow) {
      this.main.ionum++;
      this.main.ioreqs[this.main.ionum] = this;
      this.main.iodata[this.main.ionum] = new Array();
      this.main.sendRequest("job=getrow,oid=" + this.curtable.id  + ",table=" + this.curtable.tablename + this.curtable.urlappend + ",start=" + firstRow.toString() + ",end=" + lastRow.toString() + ",ionum=" + this.main.ionum + ",orderby=" + this.curtable.tablename + "." + this.curtable.dbname[this.getSortColumnIndex()] + (this.isSortAscending() ? "" : "_"));
    }
  }
});
