<?php

include __DIR__ . '/../vendor/autoload.php';

$server = new Swoole\Server('0.0.0.0', 3000);

$server->on('connect', function($server, $fd) {
  echo "Connected\n";
});

$server->on("receive", function($server, $fd, $from, $data) {
  $server->send($fd, $data);
});

$server->on('close', function($server, $fd) {
  echo "Closed\n";
});

Co::set(['hook_flags' => SWOOLE_HOOK_ALL]);

$server->start();