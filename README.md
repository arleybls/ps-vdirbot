ps-vdirbot
==========

An script to automate creation fo websites, vdirs, application pools from a set of tables on a database.


Data Model:

CREATE TABLE sites (
  S_ID       int          NOT NULL AUTO_INCREMENT,
  site       varchar(255) NOT NULL,
  ip         varchar(255) DEFAULT '*',
  port       int          DEFAULT 80,
  header     varchar(255) NOT NULL,
PRIMARY KEY (S_ID)
)
CREATE TABLE vdirs (
  VD_ID      int          NOT NULL AUTO_INCREMENT,
  flag       int          DEFAULT 1,
  site       varchar(255) NOT NULL,
  vdir       varchar(255) NOT NULL,
  pool       varchar(255) NOT NULL,  
  path       varchar(510),
PRIMARY KEY (VD_ID)
)

