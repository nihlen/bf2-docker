<?php

try {

    $bf2folder = '/volume/';
    $apiKey = '{{api_key}}';
    $settingsFiles = ['banlist.con', 'maplist.con', 'mm_bans.xml', 'modmanager.con', 'serversettings.con'];

    if (!isset($_GET['key']) || $_GET['key'] != $apiKey) {
        http_response_code(403);
        die('Forbidden');
    }

    // PB Logs
    if (isset($_GET['pblogs']) && isset($_GET['from'])) {
        $getdate = intval($_GET['from']);
        foreach(glob($bf2folder . 'svlogs/*.log') as $file) {
            if (filemtime($file) >= $getdate) {
                $contents = file_get_contents($file);
                echo $contents . "\r\n";
            }
        }

    // Chat Logs
    } else if (isset($_GET['chat']) && isset($_GET['from'])) {
        $getdate = intval($_GET['from']);
        foreach(glob($bf2folder . 'bf2dchat_*.log') as $file) {
            if (filemtime($file) >= $getdate) {
                $contents = file_get_contents($file);
                echo $contents . "\r\n";
            }
        }

    // Get settings
    } else if (isset($_GET['getsettings']) && in_array($_GET['getsettings'], $settingsFiles)) {
        echo file_get_contents($bf2folder . 'settings/' . $_GET['getsettings']);

    // Set settings
    } else if (isset($_GET['setsettings']) && in_array($_GET['setsettings'], $settingsFiles) && $_SERVER['REQUEST_METHOD'] == 'POST') {
        $content = file_get_contents("php://input");
        file_put_contents($bf2folder . 'settings/' . $_GET['setsettings'], $content);

    } else {
        http_response_code(400);
        die('Bad Request');
    }

} catch (Exception $e) {
    echo 'Caught exception: ',  $e->getMessage(), "\n";
}

?>