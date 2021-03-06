#
# == Class: librenms::config
#
# Configure a virtual host for LibreNMS
#
class librenms::config
(
    String  $system_user,
            $basedir,
    String  $server_name,
    String  $admin_user,
    String  $admin_pass,
    String  $admin_email,
            $db_user,
            $db_host,
            $db_pass,
    Hash[String, Integer[0,1]] $poller_modules,
    Integer $poller_threads

) inherits librenms::params
{
    File {
        ensure => 'present',
        mode   => '0755',
    }

    file { 'librenms-apache-site-conf':
        path    => "${::librenms::params::apache_sites_dir}/librenms.conf",
        content => template('librenms/apache_vhost.conf.erb'),
        owner   => $::os::params::adminuser,
        group   => $::os::params::admingroup,
        require => Class['::apache2::install'],
    }

    # Construct the poller module hash, with defaults coming from params.pp
    $l_poller_modules = merge($::librenms::params::default_poller_modules, $poller_modules)

    # The LibreNMS-specific rrdcached service will only work on systemd distros 
    # at the moment.
    if str2bool($::has_systemd) {
        $rrdcached_line = "\$config['rrdcached'] = \"unix:/opt/librenms/rrdcached/rrdcached.sock\";"
    } else {
        $rrdcached_line = '# rrdcached disabled by Puppet because this is not a systemd distro'
    }

    file { 'librenms-config.php':
        path    => "${basedir}/config.php",
        owner   => $system_user,
        group   => $system_user,
        content => template('librenms/config.php.erb'),
        require => Class['::librenms::install'],
    }


    php::module { 'mcrypt':
        ensure  => 'enabled',
        require => Class['::librenms::install'],
    }

    Exec {
        user    => $::os::params::adminuser,
        path    => [ '/bin', '/sbin', '/usr/bin', '/usr/sbin', '/usr/local/bin', '/usr/local/sbin' ],
    }

    if $db_host == 'localhost' {
        $build_base_php_require = [ File['librenms-config.php'], Class['::librenms::dbserver'] ]
    } else {
        $build_base_php_require = File['librenms-config.php']
    }

    exec { 'librenms-build-base.php':
        command => "php ${basedir}/build-base.php && touch ${basedir}/.build-base.php-ran",
        creates => "${basedir}/.build-base.php-ran",
        require => $build_base_php_require,
    }

    exec { 'librenms-adduser.php':
        command => "php adduser.php ${admin_user} ${admin_pass} 10 ${admin_email} && touch ${basedir}/.adduser.php-ran",
        creates => "${basedir}/.adduser.php-ran",
        require => Exec['librenms-build-base.php'],
    }

    # Without the poller-wrapper we don't get any information from snmpd daemons
    cron { 'librenms-poller-wrapper.py':
        command => "${basedir}/poller-wrapper.py ${poller_threads} > /dev/null 2>&1",
        user    => 'root',
        minute  => '*/5',
        require => Class['::librenms::install'],
    }

}
