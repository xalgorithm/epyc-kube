<?php
/*
Plugin Name: Memcached Object Cache
Description: Memcached backend for the WordPress Object Cache
Version: 1.0
Author: WordPress Infrastructure Team
*/

// Check if Memcached class exists
if (!class_exists('Memcached')) {
    // Fallback to the WordPress default cache
    return;
}

// Set up global variables
global $wp_object_cache;

// Base Memcached class for WP
class WP_Object_Cache {
    private $memcached;
    private $cache = array();
    private $blog_prefix;
    private $default_expiration = 3600; // 1 hour default

    public function __construct() {
        global $blog_id;

        $this->memcached = new Memcached();
        $this->memcached->addServer('memcached.wordpress.svc.cluster.local', 11211);
        
        // Set binary protocol and other options for better performance
        $this->memcached->setOption(Memcached::OPT_BINARY_PROTOCOL, true);
        $this->memcached->setOption(Memcached::OPT_NO_BLOCK, true);
        $this->memcached->setOption(Memcached::OPT_TCP_NODELAY, true);
        $this->memcached->setOption(Memcached::OPT_LIBKETAMA_COMPATIBLE, true);

        // Set multi-site prefix if applicable
        $this->blog_prefix = is_multisite() ? $blog_id . ':' : '';
    }

    public function add($key, $data, $group = 'default', $expire = 0) {
        $key = $this->get_cache_key($key, $group);
        
        if ($this->exists($key, $group)) {
            return false;
        }

        return $this->set($key, $data, $group, $expire);
    }

    public function get($key, $group = 'default', $force = false, &$found = null) {
        $key = $this->get_cache_key($key, $group);

        if (isset($this->cache[$group][$key]) && !$force) {
            $found = true;
            return $this->cache[$group][$key];
        }

        $value = $this->memcached->get($key);

        if ($this->memcached->getResultCode() == Memcached::RES_NOTFOUND) {
            $found = false;
            return false;
        }

        $found = true;
        $this->cache[$group][$key] = $value;
        return $value;
    }

    public function set($key, $data, $group = 'default', $expire = 0) {
        $key = $this->get_cache_key($key, $group);

        $expire = ($expire == 0) ? $this->default_expiration : $expire;
        
        $this->cache[$group][$key] = $data;
        return $this->memcached->set($key, $data, $expire);
    }

    public function delete($key, $group = 'default') {
        $key = $this->get_cache_key($key, $group);

        unset($this->cache[$group][$key]);
        return $this->memcached->delete($key);
    }

    public function flush() {
        $this->cache = array();
        return $this->memcached->flush();
    }

    public function exists($key, $group = 'default') {
        $key = $this->get_cache_key($key, $group);

        if (isset($this->cache[$group][$key])) {
            return true;
        }

        $value = $this->memcached->get($key);
        if ($this->memcached->getResultCode() == Memcached::RES_SUCCESS) {
            $this->cache[$group][$key] = $value;
            return true;
        }

        return false;
    }

    public function get_cache_key($key, $group) {
        return $this->blog_prefix . $group . ':' . $key;
    }

    public function stats() {
        return $this->memcached->getStats();
    }

    public function close() {
        $this->memcached->quit();
    }

    public function increment($key, $offset = 1) {
        return $this->memcached->increment($key, $offset);
    }

    public function decrement($key, $offset = 1) {
        return $this->memcached->decrement($key, $offset);
    }
}

// Initialize object cache
function wp_cache_init() {
    global $wp_object_cache;
    $wp_object_cache = new WP_Object_Cache();
}

function wp_cache_add($key, $data, $group = 'default', $expire = 0) {
    global $wp_object_cache;
    return $wp_object_cache->add($key, $data, $group, $expire);
}

function wp_cache_get($key, $group = 'default', $force = false, &$found = null) {
    global $wp_object_cache;
    return $wp_object_cache->get($key, $group, $force, $found);
}

function wp_cache_set($key, $data, $group = 'default', $expire = 0) {
    global $wp_object_cache;
    return $wp_object_cache->set($key, $data, $group, $expire);
}

function wp_cache_delete($key, $group = 'default') {
    global $wp_object_cache;
    return $wp_object_cache->delete($key, $group);
}

function wp_cache_flush() {
    global $wp_object_cache;
    return $wp_object_cache->flush();
}

function wp_cache_close() {
    global $wp_object_cache;
    return $wp_object_cache->close();
}

// Alias for compatibility
function wp_cache_replace($key, $data, $group = 'default', $expire = 0) {
    return wp_cache_set($key, $data, $group, $expire);
}

function wp_cache_incr($key, $offset = 1, $group = 'default') {
    global $wp_object_cache;
    $key = $wp_object_cache->get_cache_key($key, $group);
    return $wp_object_cache->increment($key, $offset);
}

function wp_cache_decr($key, $offset = 1, $group = 'default') {
    global $wp_object_cache;
    $key = $wp_object_cache->get_cache_key($key, $group);
    return $wp_object_cache->decrement($key, $offset);
}

// Load the object cache
wp_cache_init(); 