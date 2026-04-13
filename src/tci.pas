// Simple TCI client (Phase 1) - plain TCP client, parses basic TCI commands
// Implements core CAT: VFO, MODULATION, TX_ENABLE, RX_SMETER, SPOT (receive)
{$mode objfpc}
unit tci;

interface
uses rig, timer, tree, sysutils, sockets;

type
   tcictl = class(radioctl)
     public
       constructor create(debugin: boolean); override;
       procedure setconfig(cfg: string);
       procedure timer(caughtup: boolean); override;
       procedure setradiofreq(f: longint; m: modetype; vfo: char); override;
       function getradioparameters(var f: longint; var b: bandtype;
         var m: modetype): boolean; override;
     private
       host: string;
       port: integer;
       socketfd: longint;
       connected: boolean;
       inbuf: string;
       trxindex: integer;
       procedure tryconnect;
       procedure sendraw(s: string);
   end;

implementation
uses strutils;

constructor tcictl.create(debugin: boolean);
begin
  inherited create(debugin);
  host := '';
  port := 40001;
  socketfd := -1;
  connected := false;
  inbuf := '';
  trxindex := 0;
end;

procedure tcictl.setconfig(cfg: string);
var s: string; p: integer;
begin
  // expected cfg form: TCI;host:port;trxindex
  s := cfg;
  delete(s,1,4); // drop leading TCI;
  if s = '' then exit;
  p := pos(':',s);
  if p > 0 then
  begin
    host := copy(s,1,p-1);
    port := StrToIntDef(copy(s,p+1,255),40001);
  end else host := s;
  p := pos(';',host);
  // allow trailing ;trxindex
  if p > 0 then
  begin
    trxindex := StrToIntDef(copy(host,p+1,255),0);
    host := copy(host,1,p-1);
  end;
end;

procedure tcictl.tryconnect;
var addr: TInetSockAddr; res: integer;
begin
  if connected then exit;
  socketfd := fpSocket(AF_INET, SOCK_STREAM, 0);
  if socketfd < 0 then exit;
  addr.sin_family := AF_INET;
  addr.sin_port := htons(port);
  addr.sin_addr := StrToNetAddr(host);
  res := fpConnect(socketfd,@addr, SizeOf(addr));
  if res = 0 then
  begin
    // set non-blocking
    fpfcntl(socketfd, F_SETFL, O_NONBLOCK);
    connected := true;
  end else
  begin
    fpClose(socketfd);
    socketfd := -1;
    connected := false;
  end;
end;

procedure tcictl.sendraw(s: string);
begin
  if not connected then exit;
  try
    fpSend(socketfd, pchar(s)^, length(s), 0);
  except
  end;
end;

procedure tcictl.timer(caughtup: boolean);
var buf: array[0..2047] of char; rcv,len,i: integer; msg,cmd,args:string; semi: integer;
    parts: TStringArray; fval: longint; modeStr: string;
begin
  inherited timer(caughtup);
  if not connected then
  begin
    tryconnect;
    exit;
  end;
  // read available data
  rcv := fpRecv(socketfd,@buf[0], sizeof(buf), 0);
  if rcv > 0 then
  begin
    setstring(msg, buf, rcv);
    inbuf := inbuf + msg;
    // parse ; terminated messages
    while pos(';', inbuf) > 0 do
    begin
      semi := pos(';', inbuf);
      args := copy(inbuf,1,semi-1);
      delete(inbuf,1,semi);
      // args is like COMMAND:arg1,arg2,...
      cmd := '';
      if pos(':', args) > 0 then
      begin
        cmd := uppercase(copy(args,1,pos(':',args)-1));
        delete(args,1,pos(':',args));
      end else cmd := uppercase(args);
      if cmd = 'VFO' then
      begin
        // VFO:trx,channel,freq
        parts := args.Split([',']);
        if length(parts) >= 3 then
        begin
          fval := StrToIntDef(parts[2],0);
          freq := fval;
        end;
      end else if cmd = 'MODULATION' then
      begin
        parts := args.Split([',']);
        if length(parts) >= 2 then
        begin
          modeStr := uppercase(parts[1]);
          if (modeStr='USB') OR (modeStr='LSB') OR (modeStr='AM') OR (modeStr='FM') then
            mode := Phone
          else if (modeStr='RTTY') OR (modeStr='DIG') then
            mode := Digital
          else mode := CW;
        end;
      end else if cmd = 'TX_ENABLE' then
      begin
        parts := args.Split([',']);
        if length(parts)>=2 then
          txon := (uppercase(parts[1])='TRUE') OR (parts[1]='1');
      end;
      // SPOT, RX_SMETER, DEVICE, READY etc could be handled here later
    end;
  end else if rcv = 0 then
  begin
    // connection closed
    connected := false;
    if socketfd >= 0 then fpclose(socketfd);
    socketfd := -1;
  end;
end;

procedure tcictl.setradiofreq(f: longint; m: modetype; vfo: char);
var s: string; modstr: string;
begin
  freq := f;
  mode := m;
  // map mode
  case m of
    CW: modstr := 'CW';
    Digital: modstr := 'RTTY';
    else modstr := 'USB';
  end;
  // send VFO and MODULATION
  s := Format('VFO:%d,0,%d;',[trxindex,f]);
  sendraw(s);
  s := Format('MODULATION:%d,%s;',[trxindex,modstr]);
  sendraw(s);
end;

function tcictl.getradioparameters(var f: longint; var b: bandtype;
  var m: modetype): boolean;
begin
  f := freq;
  m := mode;
  b := getband(freq);
  getradioparameters := true;
end;

end.
