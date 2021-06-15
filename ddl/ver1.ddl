CREATE TABLE user 
   (
   name      varchar(255) NOT NULL default '',
   password  varchar(255) default NULL       ,
   role      varchar(255) default 'User'     ,
   namespace varchar(255) default NULL       ,
   updated   timestamp                       ,
   PRIMARY KEY (name)
   ) TYPE=innodb;

CREATE TABLE bucket
   (
   namespace           varchar(255) NOT NULL           ,
   name                varchar(255) NOT NULL           ,
   owner               varchar(255) default NULL       ,
   policy              varchar(255) default '[RW....]' ,
   policy2             varchar(255) default NULL       ,
   policychange        datetime                        ,
   custom_metadata     varchar(255) default NULL       ,
   max_size            int          default NULL       ,
   max_objects         int          default NULL       ,
   signature_cert      varchar(255) default NULL       ,
   encryption_cert     varchar(255) default NULL       ,
   updated             timestamp                       ,

   PRIMARY KEY (namespace, name)
   ) TYPE=innodb;

CREATE TABLE object
   (
   namespace       varchar(255) NOT NULL    ,
   bucket          varchar(255) default NULL,
   name            varchar(255) NOT NULL    ,
   owner           varchar(255) default NULL,
   value           mediumblob               ,
   content_type    varchar(255) default NULL,
   content_length  varchar(255) default NULL,
   content_md5     varchar(255) default NULL,
   custom_metadata varchar(255) default NULL,
   updated         timestamp                ,

   PRIMARY KEY (namespace, bucket, name)
   ) TYPE=innodb;


CREATE TABLE log
   (
   id              int(11)      auto_increment,
   user            varchar(255) not NULL      ,
   url             varchar(255) not NULL      ,
   user_agent      varchar(255)               ,
   
   verb            varchar(255) default NULL  ,
   namespace       varchar(255) default NULL  ,
   bucket          varchar(255) default NULL  ,
   object          varchar(255) default NULL  ,

   time            timestamp                  ,
   result_code     int          not NULL      ,

   PRIMARY KEY (id)
   ) TYPE=innodb;


replace into user set name="admin", password="#it2dust"    , role="admin", namespace=null;
replace into user set name="craig", password="realpassword", role="owner", namespace="craigspace";
replace into user set name="user" , password="secret"      , role="user" , namespace=null;
