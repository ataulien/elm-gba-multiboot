/**
 * NodeJS-Part of the Gameboy Advance Multiboot-Cable using Elm.
 * 
 * By Andre Taulien (2018)
 */

var SerialPort = require('serialport');
var fs = require('fs')

Elm = require("elm-flash");
var app = Elm.Main.worker()
var serial = null;

remove_commands = function(s) {
  out = ""

  for (var c of s) {
    if (c > 5) {
      out += String.fromCharCode(c);
    }
  }

  return out;
}

remove_text = function(s) {
  out = []

  for (var c of s) {
    if (c <= 5) {
      out.push(c);
    }
  }

  return out;
}


on_serial_data = function(data) {
  var list = [...data];

  var text = remove_commands(list);
  var commands = remove_text(list);

  process.stdout.write(text);

  for (var c of commands) {
    app.ports.port_on_remote_command.send(c);
  }
}


app.ports.port_initalize_serial_port.subscribe(function(args) {
  serial = new SerialPort(args, {
    baudRate: 57600,
    databits: 8,
    parity: 'none',
  });

  serial.on('data', on_serial_data);
});


app.ports.port_write_serial.subscribe(function(args) {
  serial.write(args);
});


app.ports.port_read_file_contents.subscribe(function(args) {
  var contents = [...fs.readFileSync(args)];

  app.ports.port_on_file_contents_loaded.send(contents);
});


app.ports.port_write_console.subscribe(function(args) {
  console.log("Elm: " + args);
});

app.ports.port_write_stdout.subscribe(function(args) {
  process.stdout.write(args);
});

app.ports.port_on_program_config.send(process.argv.slice(2));
