#
#class based on the dpm wiki example
#
class dpm::headnode (
    $configure_vos =  $dpm::params::configure_vos,
    $configure_gridmap =  $dpm::params::configure_gridmap,
    $configure_bdii = $dpm::params::configure_bdii,
    $configure_firewall = $dpm::params::configure_firewall,

    #Cluster options
    $local_db = $dpm::params::local_db,
    $headnode_fqdn =  $dpm::params::headnode_fqdn,
    $disk_nodes =  $dpm::params::disk_nodes,
    $localdomain =  $dpm::params::localdomain,
    $webdav_enabled = $dpm::params::webdav_enabled,
    $memcached_enabled = $dpm::params::memcached_enabled,
    #GridFtp redirection
    $gridftp_redirect = $dpm::params::gridftp_redirect,

    #dpmmgr user options
    $dpmmgr_uid =  $dpm::params::dpmmgr_uid,
    $dpmmgr_gid =  $dpm::params::dpmmgr_gid,

    #DB/Auth options
    $db_user =  $dpm::params::db_user,
    $db_pass =  $dpm::params::db_pass,
    $db_host =  $dpm::params::db_host,
    $mysql_root_pass =  $dpm::params::mysql_root_pass,
    $token_password =  $dpm::params::token_password,
    $xrootd_sharedkey =  $dpm::params::xrootd_sharedkey,
    $xrootd_use_voms =  $dpm::params::xrootd_use_voms,

    #VOs parameters
    $volist =  $dpm::params::volist,
    $groupmap =  $dpm::params::groupmap,

    #Debug Flag
    $debug = $dpm::params::debug,

    #XRootd federations
    $dpm_xrootd_fedredirs = $dpm::params::dpm_xrootd_fedredirs,

    $site_name = $dpm::params::site_name,
  
    #New DB installation vs upgrade
    $new_installation = $dpm::params::new_installation,

)inherits dpm::params {

   validate_array($disk_nodes)
   validate_bool($new_installation)
   validate_array($volist)
   
   $disk_nodes_str=join($disk_nodes,' ')

   #XRootd monitoring parameters
    if($dpm::params::xrd_report){
      $xrd_report = $dpm::params::xrd_report
    }else{
      $xrd_report  = undef
    }

    if($dpm::params::xrootd_monitor){
        $xrootd_monitor = $dpm::params::xrootd_monitor
    }else{
      $xrootd_monitor = undef
    }
    
    #
    # Set inter-module dependencies
    #
    
    Class[lcgdm::dpm::service] -> Class[dmlite::plugins::adapter::install]
    Class[lcgdm::ns::config] -> Class[dmlite::srm::service]
    Class[dmlite::head] -> Class[dmlite::plugins::adapter::install]
    Class[dmlite::plugins::adapter::install] ~> Class[dmlite::srm]
    Class[dmlite::plugins::adapter::install] ~> Class[dmlite::gridftp]
    Class[dmlite::plugins::mysql::install] ~> Class[dmlite::srm]
    Class[dmlite::plugins::mysql::install] ~> Class[dmlite::gridftp]
    Class[fetchcrl::service] -> Class[xrootd::config]

    if($memcached_enabled){
       Class[dmlite::plugins::memcache::install] ~> Class[dmlite::dav::service]
       Class[dmlite::plugins::memcache::install] ~> Class[dmlite::gridftp]
       Class[dmlite::plugins::memcache::install] ~> Class[dmlite::srm]
    }


    #
    # MySQL server setup 
    #
    if ($local_db) {
      Class[mysql::server] -> Class[lcgdm::ns::service]

      $override_options = {
      	'mysqld' => {
            'max_connections'    => '1000',
            'query_cache_size'   => '256M',
            'query_cache_limit'  => '1MB',
            'innodb_flush_method' => 'O_DIRECT',
            'innodb_buffer_pool_size' => '1000000000',
            'bind-address' => '0.0.0.0',
          }
    	}
      
      class{'mysql::server':
    	service_enabled   => true,
        root_password => $mysql_root_pass,
        override_options => $override_options,
	create_root_user => $new_installation,
        }
    }
   

    #
    # DPM and DPNS daemon configuration.
    #
    class{'lcgdm':
      dbflavor => 'mysql',
      dbuser   => $db_user,
      dbpass   => $db_pass,
      dbhost   => $db_host,
      mysqlrootpass =>  $mysql_root_pass,
      domain   => $localdomain,
      volist   => $volist,
      uid      => $dpmmgr_uid,
      gid      => $dpmmgr_gid,
    }

    #
    # RFIO configuration.
    #
    class{'lcgdm::rfio':
      dpmhost => $::fqdn,
    }

    #
    # Entries in the shift.conf file, you can add in 'host' below the list of
    # machines that the DPM should trust (if any).
    #
    lcgdm::shift::trust_value{
      'DPM TRUST':
        component => 'DPM',
        host      => "$disk_nodes_str $headnode_fqdn";
      'DPNS TRUST':
        component => 'DPNS',
        host      => "$disk_nodes_str $headnode_fqdn";
      'RFIO TRUST':
        component => 'RFIOD',
        host      => "$disk_nodes_str $headnode_fqdn",
        all       => true
    }
    lcgdm::shift::protocol{'PROTOCOLS':
      component => 'DPM',
      proto     => 'rfio gsiftp http https xroot'
    }
    if($gridftp_redirect){
      lcgdm::shift::protocol_head{"GRIDFTP":
             component => "DPM",
             protohead => "FTPHEAD",
             host      => "${::fqdn}",
      }  
    }

    if($configure_vos){
	dpm::util::add_dpm_voms {$volist:}
    }

   if($configure_gridmap){
      #setup the gridmap file
      lcgdm::mkgridmap::file {'lcgdm-mkgridmap':
        configfile   => '/etc/lcgdm-mkgridmap.conf',
        localmapfile => '/etc/lcgdm-mapfile-local',
        logfile      => '/var/log/lcgdm-mkgridmap.log',
        groupmap     => $groupmap,
        localmap     => {'nobody'        => 'nogroup'}
      }
    
    }

    #
    # dmlite configuration.
    #
    class{'dmlite::head':
      token_password => $token_password,
      mysql_username => $db_user,
      mysql_password => $db_pass,
    }

    #
    # Frontends based on dmlite.
    #
    if($webdav_enabled){
      Class[dmlite::plugins::adapter::install] ~> Class[dmlite::dav]
      Class[dmlite::plugins::mysql::install] ~> Class[dmlite::dav]
      Class[dmlite::install] ~> Class[dmlite::dav::config]
      Dmlite::Plugins::Adapter::Create_config <| |> -> Class[dmlite::dav::install]

      class{'dmlite::dav':}
    }
    class{'dmlite::srm':}
    class{'dmlite::gridftp':
      dpmhost => $::fqdn, 
      remote_nodes => $gridftp_redirect ? {
        1 => join(suffix($disk_nodes, ':2811'), ','),
        0 => undef,
      },    
    }


    # The XrootD configuration is a bit more complicated and
    # the full config (incl. federations) will be explained here:
    # https://svnweb.cern.ch/trac/lcgdm/wiki/Dpm/Xroot/PuppetSetup

    #
    # The simplest xrootd configuration.
    #
    class{'xrootd::config':
      xrootd_user  => $dpmmgr_user,
      xrootd_group => $dpmmgr_user,
    }
    ->
    class{'dmlite::xrootd':
          nodetype             => [ 'head' ],
          domain               => $localdomain,
          dpm_xrootd_debug     => $debug,
          dpm_xrootd_sharedkey => $xrootd_sharedkey,
          xrootd_use_voms      => $xrootd_use_voms,
          dpm_xrootd_fedredirs => $dpm_xrootd_fedredirs,
          xrd_report           => $xrd_report,
          xrootd_monitor       => $xrootd_monitor,
          site_name            => $site_name
   }

   if($memcached_enabled)
   {
     class{'memcached':
       max_memory => 512,
       listen_ip => '127.0.0.1',

     }
     ->
     class{'dmlite::plugins::memcache':
       expiration_limit => 600,
       posix            => 'on',
       func_counter     => 'on',
     }
   }

   if ($configure_bdii)
   {
    #bdii installation and configuration with default values
    include('bdii')

    # GIP installation and configuration
    class{'lcgdm::bdii::dpm':
       sitename => $site_name,
       vos      => $volist ,
    }

   }

  #limit conf

   $limits_config = {
    '*' => {
      nofile => { soft => 65000, hard => 65000 },
      nproc  => { soft => 65000, hard => 65000 },
    }
   }
   class{'limits':
    config    => $limits_config,
    use_hiera => false
  }

  if ($configure_firewall) {
  #
  # The firewall configuration
  #
  firewall{'050 allow http and https':
    proto  => 'tcp',
    dport  => [80, 443],
    action => 'accept'
  }
  firewall{'050 allow rfio':
    state  => 'NEW',
    proto  => 'tcp',
    dport  => '5001',
    action => 'accept'
  }
  firewall{'050 allow rfio range':
    state  => 'NEW',
    proto  => 'tcp',
    dport  => '20000-25000',
    action => 'accept'
  }
  firewall{'050 allow gridftp control':
    state  => 'NEW',
    proto  => 'tcp',
    dport  => '2811',
    action => 'accept'
  }
  firewall{'050 allow gridftp range':
    state  => 'NEW',
    proto  => 'tcp',
    dport  => '20000-25000',
    action => 'accept'
  }
  firewall{'050 allow srmv2.2':
    state  => 'NEW',
    proto  => 'tcp',
    dport  => '8446',
    action => 'accept'
  }
  firewall{'050 allow xrootd':
    state  => 'NEW',
    proto  => 'tcp',
    dport  => '1095',
    action => 'accept'
  }
  firewall{'050 allow cmsd':
    state  => 'NEW',
    proto  => 'tcp',
    dport  => '1094',
    action => 'accept'
  }

  firewall{'050 allow DPNS':
    state  => 'NEW',
    proto  => 'tcp',
    dport  => '5010',
    action => 'accept'
  }
  firewall{'050 allow DPM':
    state  => 'NEW',
    proto  => 'tcp',
    dport  => '5015',
    action => 'accept'
  }
    }

}
