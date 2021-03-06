class dpm::head_disknode (
    $configure_vos =  $dpm::params::configure_vos,
    $configure_gridmap =  $dpm::params::configure_gridmap,
    $configure_bdii = $dpm::params::configure_bdii,
    $configure_default_pool = $dpm::params::configure_default_pool,
    $configure_default_filesystem = $dpm::params::configure_default_filesystem,
    $configure_repos = $dpm::params::configure_repos,
    $configure_dome =  $dpm::params::configure_dome,
    $configure_domeadapter = $dpm::params::configure_domeadapter,

    #repo list
    $repos =  $dpm::params::repos,

    #cluster options
    $local_db = $dpm::params::local_db,
    $headnode_fqdn =  $dpm::params::headnode_fqdn,
    $disk_nodes =  $dpm::params::disk_nodes,
    $localdomain =  $dpm::params::localdomain,
    $webdav_enabled = $dpm::params::webdav_enabled,
    $memcached_enabled = $dpm::params::memcached_enabled,

    #dpmmgr user options
    $dpmmgr_uid =  $dpm::params::dpmmgr_uid,
    $dpmmgr_gid =  $dpm::params::dpmmgr_gid,
    $dpmmgr_user =  $dpm::params::dpmmgr_user,

    #mysql override
    $mysql_override_options =  $dpm::params::mysql_override_options,

    #DB/Auth options
    $db_user =  $dpm::params::db_user,
    $db_pass =  $dpm::params::db_pass,
    $db_host =  $dpm::params::db_host,
    $db_manage = $dpm::params::db_manage,
    $mysql_root_pass =  $dpm::params::mysql_root_pass,
    $token_password =  $dpm::params::token_password,
    $xrootd_sharedkey =  $dpm::params::xrootd_sharedkey,
    $xrootd_use_voms =  $dpm::params::xrootd_use_voms,

    #VOs parameters
    $volist =  $dpm::params::volist,
    $groupmap =  $dpm::params::groupmap,
    $localmap = $dpm::params::localmap,

    #Debug Flag
    $debug = $dpm::params::debug,

    #XRootd federations
    $dpm_xrootd_fedredirs = $dpm::params::dpm_xrootd_fedredirs,

    #xrootd monitoring
    $xrd_report = $dpm::params::xrd_report,
    $xrootd_monitor = $dpm::params::xrootd_monitor,

    $site_name = $dpm::params::site_name,
 
    #admin DN
    $admin_dn = $dpm::params::admin_dn,

    #New DB installation vs upgrade
    $new_installation = $dpm::params::new_installation,
     
    #pools filesystem 
    $pools = $dpm::params::pools,
    $filesystems = $dpm::params::filesystems,
    $mountpoints = $dpm::params::mountpoints,

)inherits dpm::params {
   
    validate_array($disk_nodes)
    validate_bool($new_installation)
    validate_array($volist)
    validate_hash($mysql_override_options)

    $disk_nodes_str=join($disk_nodes,' ')

    if ($configure_repos){
        create_resources(yumrepo,$repos)
    }

    #
    # Set inter-module dependencies
    #
    if $configure_domeadapter {
      Class[dmlite::head] -> Class[dmlite::plugins::domeadapter::install]
      Class[dmlite::plugins::domeadapter::install] ~> Class[dmlite::gridftp]
    }else {
      Class[lcgdm::dpm::service] -> Class[dmlite::plugins::adapter::install]
      Class[dmlite::head] -> Class[dmlite::plugins::adapter::install]
      Class[dmlite::plugins::adapter::install] ~> Class[dmlite::srm]
      Class[dmlite::plugins::adapter::install] ~> Class[dmlite::gridftp]
    }

    Class[lcgdm::ns::config] -> Class[dmlite::srm::service]
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
    if ($local_db and $db_manage) {
      Class[mysql::server] -> Class[lcgdm::ns::service]
      
      class{'mysql::server':
    	service_enabled   => true,
        root_password => $mysql_root_pass,
	override_options => $mysql_override_options,
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
      dbmanage => $db_manage,
      mysqlrootpass => $mysql_root_pass,
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

    if($configure_vos){
      $newvolist = reject($volist,'\.')
      dpm::util::add_dpm_voms{$newvolist:}
    }

    if($configure_gridmap){
      #setup the gridmap file
      lcgdm::mkgridmap::file {'lcgdm-mkgridmap':
        configfile   => '/etc/lcgdm-mkgridmap.conf',
	mapfile      => '/etc/lcgdm-mapfile',
        localmapfile => '/etc/lcgdm-mapfile-local',
        logfile      => '/var/log/lcgdm-mkgridmap.log',
        groupmap     => $groupmap,
        localmap     => $localmap
      }
      
       exec{'/usr/sbin/edg-mkgridmap --conf=/etc/lcgdm-mkgridmap.conf --safe --output=/etc/lcgdm-mapfile':
        require => Lcgdm::Mkgridmap::File['lcgdm-mkgridmap'],
      	unless => '/usr/bin/test -s /etc/lcgdm-mapfile',
      }
    }

    #
    # dmlite configuration.
    #
    class{'dmlite::head':
      adminuser      => $admin_dn,
      token_password => $token_password,
      mysql_username => $db_user,
      mysql_password => $db_pass,
      mysql_host     => $db_host,
      enable_dome    => $configure_dome,
      enable_disknode => true,
      enable_domeadapter => $configure_domeadapter,
    }

    #
    # Frontends based on dmlite.
    #
    if($webdav_enabled){
       if $configure_domeadapter {
        Class[dmlite::plugins::domeadapter::install] ~> Class[dmlite::dav]
        Dmlite::Plugins::Domeadapter::Create_config <| |> -> Class[dmlite::dav::install]
      } else {
        Class[dmlite::plugins::adapter::install] ~> Class[dmlite::dav]
        Dmlite::Plugins::Adapter::Create_config <| |> -> Class[dmlite::dav::install]
      }
      Class[dmlite::plugins::mysql::install] ~> Class[dmlite::dav]
      Class[dmlite::install] ~> Class[dmlite::dav::config]

      class{'dmlite::dav':}
    }
    class{'dmlite::srm':}
    class{'dmlite::gridftp':
      dpmhost => $::fqdn,
      enable_dome_checksum => $configure_domeadapter,
    }

    #
    # The simplest xrootd configuration.
    #
    class{'xrootd::config':
      xrootd_user  => $dpmmgr_user,
      xrootd_group => $dpmmgr_user,
    }
    if $xrd_report or $xrootd_monitor {
	    class{'dmlite::xrootd':
        	  nodetype             => [ 'head','disk' ],
	          domain               => $localdomain,
	          dpm_xrootd_debug     => $debug,
	          dpm_xrootd_sharedkey => $xrootd_sharedkey,
	          xrootd_use_voms      => $xrootd_use_voms,
	          dpm_xrootd_fedredirs => $dpm_xrootd_fedredirs,
	          xrd_report           => $xrd_report,
        	  xrootd_monitor       => $xrootd_monitor,
	          site_name            => $site_name
    	    } 
    }
    else {
          class{'dmlite::xrootd':
                  nodetype             => [ 'head','disk' ],
                  domain               => $localdomain,
                  dpm_xrootd_debug     => $debug,
                  dpm_xrootd_sharedkey => $xrootd_sharedkey,
                  xrootd_use_voms      => $xrootd_use_voms,
                  dpm_xrootd_fedredirs => $dpm_xrootd_fedredirs,
                  site_name            => $site_name

    	}
   }
   #install n2n plugin in case of atlas fed
   $array_feds =  keys($dpm_xrootd_fedredirs)
   if member($array_feds, 'atlas') {
        package{'xrootd-server-atlas-n2n-plugin':
          ensure => present,
        }
   }

   if($memcached_enabled)
   {
     class{'memcached':
       max_memory => 2000,
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
    Class[bdii::install] -> Class[lcgdm::bdii::dpm]
    Class[lcgdm::bdii::dpm] -> Class[bdii::service]

    # GIP installation and configuration
    class{'lcgdm::bdii::dpm':
       sitename => $site_name,
       vos      => $volist,
    }

   }
  
  #pools configuration
  #
  if ($configure_default_pool) {
    dpm::util::add_dpm_pool {$pools:}
  }
  #
  #
  # You can define your filesystems
  #
  if ($configure_default_filesystem) {
    Class[lcgdm::base::config] ->
     file{
      $mountpoints:
        ensure => directory,
        owner => $dpmmgr_user,
        group => $dpmmgr_user,
        mode =>  '0775';
     }
     -> dpm::util::add_dpm_fs {$filesystems:}
  }
  
 include dmlite::shell
}
