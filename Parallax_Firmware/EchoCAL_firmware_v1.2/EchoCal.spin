'' EchoCal.spin
''
'' This is the main program for the NEFSC mobile echosounder calibration system.
''
'' The EchoCAL system is used by the acoustic researchers at the Northeast Fisheries Science
'' Center to perform EK60 echosounder calibrations on any research vessels. This is a portable system in which
'' all of the power and control signals are self contained in ruggedized Pelican cases. Each downrigger is controlled
'' wirelessly from a remote PC. This system uses the ZigBee wireless mesh network protocol as the controlling
'' network.
''
'' 
'' Revision History:
''      Version 1.00 :  17 April 2011
''          1. Initial Release by:
''                Joseph M. Godlewski
''                Electronics Engineer
''                NOAA/NMFS, Northeast Fisheries Science Center
''                166 Water Street, Woods Hole, MA  02543
''                Telephone # (508) 495-2039
''                Email:  Joseph.Godlewski@noaa.gov
''
''
''      Version 1.20 :  7 September 2018
''          1. Inserted function "monitor_Comm" just after the "setup_Cal" procedure execution in the Main procedure
''             so that the operator can program the EchoCAL downrigger control box.
''
''          2. Added variable "ms" to the "monitor_Comm" function so that we can vary the timeout in the
''             serial port read funtion. Allows us to program the Downrigger Control Box if needed when we first
''             power up the box.
''
''
CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000

  FWVersion     = 1.2

  '  hardware pin-out and configuration parameters
{ --------------------  Production Board RS232 Pinout... ------------------------}
  serialRx      = 31                  '  RS232 serial out Rx pin
  serialTx      = 30                  '  RS232 serial out Tx pin
  serialBaud    = 9_600               '  RS232 serial out baud rate

{ --------------------  Production Board ZigBee Wireless Pinout... ------------------------}

  ZB_serRX      = 20                  '  ZigBee Wireless Tranceiver Tx pin...
  ZB_serTX      = 19                  '  ZigBee Wireless Tranceiver Rx pin...

  ZBBaud        = 9_600               '  ZigBee Wireless Tranceiver baud rate..

{ --------------------  Secondary EEPROM Pinout... ------------------------}      
  i2cSDA        = 27                  '  Secondary EEPROM SDA pin
  i2cSCL        = 26                  '  Secondary EEPROM SCL pin
  EEPROM_ADDR   = %1010_0000          '  24LC256 ic2 device address

{ --------------------  Motor Control Relays... ------------------------}    
  motorOUT      = 12
  motorIN       = 10

{ --------------------  Encoder Quadrature Signals... ------------------------}    
  sigA          = 0                   '  Signal A from Downrigger Encoder.
  sigB          = 1                   '  Signal B from Downrigger Encoder.  90 deg out of phase with "sigA".

{ --------------------  Direction Indicators... ------------------------}    
  indOUT        = 3                   '  Red LED showing motor is being driven in the outward direction.
  indIN         = 4                   '  Green LED showing motor is being driven in the inward direction.

  crsTime       = 1_000               '  Used to control the delay time for WAITCNT statements.  (ie. 1.0 seconds)
  fineTime      = 200                 '  Used to control the delay time for WAITCNT statements.  (ie. 0.2 seconds)

  '  Secondary EEPROM data addresses. Secondary EEPROM is used to store setup parameters.
  
  lenAddr       = $FFE0               '  First byte is length of serial identifier stored on Secondary EEPROM

  serAddr       = $FFE1               '  Serial Identifier occupies bytes $FFE1-$FFEF stored on Secondary EEPROM

  oneByte       = 8                   '  Flag to read only one Byte [8  bits] from EEPROM...
  oneWord       = 16                  '  Flag to read only one Word [16 bits] from EEPROM...
  oneLong       = 32                  '  Flag to read only one Long Data Word [32 bits] from EEPROM...

{ --------------------  Generic constant declarations... ------------------------}

  ON            = 1                   '  Generic ON  flag..  --- NEFSC setup
  OFF           = 0                   '  Generic OFF flag..  --- NEFSC setup

  HI            = 1                   '  Set HI indicator..  --- NEFSC setup
  LO            = 0                   '  Set LO indicator..  --- NEFSC setup

  RS232         = 0                   '  Generate Serial Communication for RS-232 port..
  ZIGBEE        = 1                   '  Generate Serial Communication for ZigBee Wireless transceiver port..

  delaytime     = 100                 '  Used to control the delay time for WAITCNT statements.  (ie. 0.1 seconds)

  maxIDX        = 200                 '  Maximum index for all vector variables.

  '  Commands issued from PC to control EK60 Mobile Cal microcontroller functions..

  cPRGM         = $0A                 '  "Program" EchoCal microcontroller and wireless ZigBee Transceiver..
  cPING         = $FF                 '  "PING" command to EchoCal from PC.

OBJ
  mcuSerial[2]  : "Extended_FDSerialNew"
  f             : "FloatMath"
  fstr          : "FloatString"
  base_i2c      : "Basic_I2C_Driver"
  encoder       : "Handle_Encoder"

VAR

  long  Delay_MS
  long  lCNT
  long  lTICK

  byte  bDIR
  byte  bSTATE
  
'-------------- Command string received from controlling PC.  -------------------------------
'-------------- Example := $EK60Cxxx,cmd,in,coarse            -------------------------------

  byte  rx_Buffer[80]                 'Receive buffer string of 80 characters..
  byte  temp_Buffer[80]               'Temporary buffer string of 80 characters..
  byte  cName[15]                     'Array to hold ID of command string from controlling PC.
  byte  cCMD[5]                       'Array to hold command string from controlling PC.
  byte  cDIR[5]                       'Array to hold direction string from controlling PC.
  byte  cSPD[5]                       'Array to hold "CRSE" or "FINE" string from controlling PC.

'-------------- Command string sent back to the controlling PC. -------------------------------
'-------------- Example := $EK60Cxxx,rsp,in,count               -------------------------------
  byte  cRspCMD[5]                    'Array to hold command string to controlling PC.
  byte  cRspDIR[5]                    'Array to hold direction string to controlling PC.
  byte  cRspCNT[10]                   'Array to hold number of revolutions string to controlling PC.

  byte  prompt[15]                    'Array to hold Prompt string from ZigBee wireless transceiver.

  byte  cSerNum[15]                   'Holds the Serial Number of the device.

PUB Main | x, idx
''  This is the main procedure for EchoCAL. It does all of the initial setup of the systems parameters as 
'' well as handling all of the communications with the host PC and the ZigBee Wireless Transceiver.

  '  Initialize i2c object
  base_i2c.Initialize(i2cSCL)                           ' Initialize Boot EEPROM....

  setup_EchoCal                                         ' Perform all of the parameter initialization here...

  monitor_Comm(10_000)                                  ' Monitor the RS232 communication channel to see
                                                        ' if PC wants to do something.. This procedure will
                                                        ' timeout in 10 seconds if nothing is received on the
                                                        ' RS232 serial port. Allows us to program the Downrigger
                                                        ' Control Box.

'    Read in serial identifier length..
  idx := 0
  idx := readEEPROM(i2cSCL, EEPROM_ADDR, lenAddr, oneByte)

'    Read in serial number and store in variable "cSerNum"..
  if idx > 0 AND idx < 15

    bytefill(@cSerNum, 0, 15)
    repeat x from 0 to idx-1

      cSerNum[x] := readEEPROM(i2cSCL, EEPROM_ADDR, serAddr+x, oneByte)
      waitcnt(150_000 + cnt)

  else

'     If serial number hasn't been ID'd yet, lets use a generic #.
    bytemove(@cSerNum, string("EK60CXXX"), strsize(string("EK60CXXX")))

  mcuSerial[RS232].str(string("Serial Number is: "))
  mcuSerial[RS232].str(@cSerNum)
  mcuSerial[RS232].str(string(13,10))

  repeat

    monitor_ZigBee                                      ' Monitor the ZigBee wireless communication channel to see if the
                                                        ' remote controller wants this system to do something.

  return

PUB  setup_EchoCal | x
''    This procedure will start the serial communication COGs for both RS232 and Zigbee communications.
'' The RS232 communications are for Programming and Debug purposes. The ZigBee communication path provides
'' the interaction between the downrigger and the remote PC.
'' 

  mcuSerial[RS232].start(serialRx, serialTx, 0, serialBaud)
  mcuSerial[ZIGBEE].start(ZB_serRX, ZB_serTX, 0, ZBBaud)        'Start the serial communications with the ZigBee transceiver..

  encoder.start(sigA, sigB)                                     'Start monitoring the encoder output in a new cog.

  return

PUB  monitor_Comm (ms) | x, rData
''    This procedure will monitor the RS232 comm port and act on any commands received from the PC.
'' Variable "rData" is the receive buffer which will store the commands/data received from the PC.
''
'' Rev 1.20: Passed in variable "ms" so that we can vary the timeout for the serial read function "rxHexTime".

'  rData := mcuSerial[RS232].rxHexTime(200)
  rData := mcuSerial[RS232].rxHexTime(ms)

  if rData <> 0
    case rData
      cPRGM:                                            ' If "cPRGM" (program) command is received from the PC:
        handle_Program                                  ' Program the ZigBee transceiver and other parameters...

      cPING:                                            ' If "cPING" (ping) command is received from the PC:
        handle_Ping                                     ' Send a message back to PC telling of system status...

      OTHER:                                            ' If no command is received from the PC (default mode):
'        quit                                           ' Leave CASE statement, no message was received from the PC...

  return

  
PUB  monitor_ZigBee | x, y, cData, timeout, dDir, rCMD, rCNT, dCNT, rTICK, rSTATE, rPSTATE, rDIR
''    This procedure will monitor the ZigBee wireless transceiver port and act on any commands received from the PC.
'' Variable "cData" is the receive buffer which will store the commands/data received from the PC.
'' Data received from the ZigBee transceiver should be a command string from the controlling PC that tells this device
'' what it should do. The data string should look like the following:
''                 $EK60Cxxx,cmd,dir,speed<CR>
'' where:
''        $EK60Cxxx := device serial number
''        cmd       := command identifier (ie. This device is commanded to do something.)
''                              Note: ASCII string "cmd" = command downrigger to turn;
''                                    ASCII string "zero" = zero the counter string;
''                                    ASCII string "read" = read the current counter value and return value to PC.
''                                    ASCII string "updt" = update the counter to the value supplied in the "dir" data field.
''
''        dir       := direction that we want the downrigger to turn. (ie. "in" or "out"). Could also be a new "count" value
''                     if we are commanded to update the counter for the encoder.
''
''        speed     := length of time to turn the motor. (ie. "coarse" or "fine")
''
'' Once the command has been processed and the desired actions taken, the Propeller microcontroller will respond with
'' the following ASCII string indicating to the PC that it has completed the commanded task:
''                 $EK60Cxxx,rsp,rCNT,dir<CR>
'' where:
''        $EK60Cxxx := device serial number
''
''        rsp       := response identifier (ie. This device has done something, and is responding.)
''
''        rCNT      := number of counts that the encoder has detected. The number of counts relates to the number of times
''                     that the motor reel has rotated.
''
''        dir       := direction that the motor turned.
''

  bytefill(@cRspCMD, 0, 5)                              'Initialize the cRspCMD string field.
  bytefill(@cRspDIR, 0, 5)                              'Initialize the cRspDIR string field.
  bytefill(@cRspCNT, 0, 10)                             'Initialize the cRspCNT string field.

  mcuSerial[ZIGBEE].RxStr(@rx_Buffer)                   'Get the data from the ZIGBEE wireless transceiver port.

  x := strsize(@rx_Buffer)

  if x > 0                                              'If the receive buffer is > than 0, we have data. Lets process it.

    mcuSerial[RS232].str(string("Command Received = "))
    mcuSerial[RS232].str(@rx_Buffer)
    mcuSerial[RS232].str(string(13,10))

    parseData(@rx_Buffer)                               'Parse the data received from the control PC.
    if strcomp(@cName, @cSerNum)                        'If the string received from PC has the same ID as the serial number,
                                                        'we can process the rest of the data in the string.
      if strcomp(@cCMD, string("zero"))                 'If command from PC is "zero" the counter, then let's do it.

        rCNT := encoder.zeroCNT

      elseif strcomp(@cCMD, string("read"))             'If command from PC is "read", then we will read the current counter value.

        rCNT := encoder.readCNT                         'Get the current count from the encoder output.
       
      elseif strcomp(@cCMD, string("updt"))             'If command from PC is "updt", then we will update the counter.

        dCNT := StrToFloat(@cDIR)                       'The cDIR field of the command string will contain the counter value.
        dCNT := f.FTrunc(dCNT)
        rCNT := encoder.updateCNT(dCNT)                 'The update command string will have the updated count variable
                                                        'sent in the "cDIR" position of the command string. We need to
                                                        'convert it into a floating point number and then update the
                                                        'count variable in "Handle_Encoder" code section.
       
      else

        if strcomp(@cDIR, string("out"))                'Which direction does the operator want the downrigger to move?
          dDir := 0
        else
          dDir := 1

        if strcomp(@cSPD, string("fine"))               'What speed does the operator want the motor to rotate?
          timeout := fineTime
        else
          timeout := crsTime
        
        motorControl(dDir, timeout)                     'Let's control the motor according to the direction commanded
                                                        'from the control PC.
      rDIR := encoder.readDIR                           'Read the direction that the encoder thinks the motor is moving.
'     directionLED(rDIR)                                'Illuminate the proper LED in relation to the direction that the
                                                        'motor is turning.

      mcuSerial[RS232].str(string("Encoder Direction =  "))
      mcuSerial[RS232].dec(rDIR)
      mcuSerial[RS232].str(string(13,10))

      rCMD := string("rsp")
      bytemove(@cRspCMD, rCMD, strsize(rCMD))

      rTICK := encoder.readTICK                         'Get the TICK count from the encoder output.
      mcuSerial[RS232].str(string("Encoder TICK count = "))
      mcuSerial[RS232].dec(rTICK)
      mcuSerial[RS232].str(string(13,10))

      rCNT := encoder.readCNT                           'Get the count from the encoder output.
      mcuSerial[RS232].str(string("Encoder count = "))
      mcuSerial[RS232].dec(rCNT)
      mcuSerial[RS232].str(string(13,10))
      
      bytemove(@cRspDIR, @cDIR, strsize(@cDIR))

' -------------------Send Response back to controlling PC. -------------
      mcuSerial[ZIGBEE].str(string("$"))
      mcuSerial[ZIGBEE].str(@cSerNum)
      mcuSerial[ZIGBEE].str(string(","))
      mcuSerial[ZIGBEE].str(@cRspCMD)
      mcuSerial[ZIGBEE].str(string(","))
'     mcuSerial[ZIGBEE].str(@cRspCNT)
      mcuSerial[ZIGBEE].dec(rCNT)
      mcuSerial[ZIGBEE].str(string(","))
      mcuSerial[ZIGBEE].str(@cRspDIR)
      mcuSerial[ZIGBEE].str(string(13))
'------------------------------------------------------------------------

' -------------------Mirror Response back. (Debug only.) ----------------
      mcuSerial[RS232].str(string("$"))
      mcuSerial[RS232].str(@cSerNum)
      mcuSerial[RS232].str(string(","))
      mcuSerial[RS232].str(@cRspCMD)
      mcuSerial[RS232].str(string(","))
      mcuSerial[RS232].dec(rCNT)
      mcuSerial[RS232].str(string(","))
      mcuSerial[RS232].str(@cRspDIR)
      mcuSerial[RS232].str(string(13,10))
'------------------------------------------------------------------------
      
    else
      mcuSerial[RS232].str(string("Command String does not agree with serial number."))
      mcuSerial[RS232].str(string(13,10))
    
  return

PUB  parseData (rxBuffer) | lenBuffer, x, idx
''    This procedure will parse the data string "rxBuffer" that came from the controlling PC. 
'' The data string should look like the following:
''                 $EK60Cxxx,cmd,dir,speed
'' where:
''        $EK60Cxxx := device serial number
''        cmd       := command identifier (ie. This device is commanded to do something.)
''        dir       := direction that we want the downrigger to turn. (ie. "in" or "out")
''        speed     := length of time to turn the motor. (ie. "coarse" or "fine")

  bytefill(@temp_Buffer, 0, 80)                         'Initialize the temporary receive buffer.
  bytefill(@cName, 0, 15)                               'Initialize the cName string field.
  bytefill(@cCMD, 0, 5)                                 'Initialize the cCMD string field.
  bytefill(@cDIR, 0, 4)                                 'Initialize the cDIR string field.
  bytefill(@cSPD, 0, 5)                                 'Initialize the cSPD string field.

  lenBuffer := strsize(rxBuffer)                        'Get the size of the receive buffer.
  bytemove(@temp_Buffer, rxBuffer, lenBuffer)           'Create a temporary copy of the received data string.
  x := 0
  idx := 0

'---- Grab data from string and store in appropriate data fields.  ------...
  if temp_Buffer[0] == "$"

    mcuSerial[RS232].str(string("Processing command string: "))
    mcuSerial[RS232].str(@temp_Buffer)
    mcuSerial[RS232].str(string(13,10))

    x++                                                 'Increment temp_Buffer array pointer
'---- Get cName data field. ---..
    repeat until (temp_Buffer[x] == ",") OR (x > lenBuffer-1)
      cName[idx] := temp_Buffer[x]                      'Fill the ID name character field.
      x++                                               'Increment pointers
      idx++
    x++                                                 'Increment temp_Buffer array pointer
    idx := 0                                            'Reset character field pointer.
'---- Get cCMD data field. ---..
    repeat until (temp_Buffer[x] == ",") OR (x > lenBuffer-1)
      cCMD[idx] := temp_Buffer[x]                       'Fill the command character field.
      x++                                               'Increment pointers
      idx++
    x++                                                 'Increment temp_Buffer array pointer
    idx := 0                                            'Reset character field pointer.
'---- Get cDIR data field. ---..
    repeat until (temp_Buffer[x] == ",") OR (x > lenBuffer-1)
      cDIR[idx] := temp_Buffer[x]                       'Fill the direction character field.
      x++                                               'Increment pointers
      idx++
    x++                                                 'Increment temp_Buffer array pointer
    idx := 0                                            'Reset character field pointer.
'---- Get cSPD data field. ---..
    repeat until (temp_Buffer[x] == ",") OR (x > lenBuffer-1)
      cSPD[idx] := temp_Buffer[x]                       'Fill the speed character field.
      x++                                               'Increment pointers
      idx++

  else
    mcuSerial[RS232].str(string("ERROR: Invalid command string: "))
    mcuSerial[RS232].str(@temp_Buffer)
    mcuSerial[RS232].str(string(13,10))
  
  return
  
PUB  motorControl(iDirection, dTime) | x, idx
''    This procedure will control the direction of the Downrigger's motor movement. Relays K1 and K2 are hooked up
''in parallel with the Downrigger's direction toggle switch. Depending on which direction the controlling PC requests,
''either relay K1 or K2 will be activated for a set period of time. The Propeller microprocessor will provide the control
''signals for the relays.
''   Note: Microcontroller pin P10 controls relay K1. Pin P12 controls relay K2.
''
''The CANNON Mag 5HS downriggers require more time to move in the "IN" direction as compared to the "OUT" direction.
''It seems that when the downrigger moves in the "IN" direction, more load is placed on the motor, and it takes longer for
''the motor to overcome inertia before it can move. As such, we will add an additional 100 ms to the delaytime on
''the "IN" direction to give the motor enough time to move.
''
  DIRA[motorOUT..motorIN]~~                             'Set motorOUT (pin P10) and motorIN (pin P12) to an OUTPUT...
  OUTA[motorOUT..motorIN]~                              'Set both pins LO to deactivate the relays..

  case iDirection
    0:
      OUTA[motorOUT..motorIN] := %100                   'Set motorOUT pin HI, thus activating relay K1. This will
                                                        'force the Downrigger motor to rotate in the OUT direction.
      waitcnt(clkfreq / 1_000 * dTime + cnt)            'Delay a bit to allow motor to rotate..

    1:
      OUTA[motorOUT..motorIN] := %001                   'Set motorIN pin HI, thus activating relay K2. This will
                                                        'force the Downrigger motor to rotate in the IN direction.

      waitcnt(clkfreq / 1_000 * (dTime + 100) + cnt)    'Delay a bit to allow motor to rotate..

    OTHER:
      OUTA[motorOUT..motorIN] := %000                   'Set both pins LO. This deactivates both relays and stops
                                                        'the Downrigger motor. 


  OUTA[motorOUT..motorIN] := %000                       'Set both pins LO to deactivate the relays..
  

  return

PUB  handle_Program | check_Data, cData, dData, cmd, cNum, rcvd, i, x, numLength
''    This procedure will handle the programming of the Digi XBEE_PRO Wireless Transceiver as well as the Parallax
'' Microcontroller settings.
'' Note:
''     1. To program the XBEE_PRO transceiver, you must first send the ASCII command "+++".
''       When the XBEE_PRO transceiver receives the +++ command, it will send the following ASCII response "OK"<CR><LF>.
''       The XBEE_PRO will slave to the RS-232 port and wait for further instructions for a preprogramed period of time.
''       When the time period expires, the XBEE_PRO goes back to its default mode of listening to the wireless link.
''     2. Once the Propeller microcontroller has received the "OK"<CR><LF> prompt from the XBEE_PRO, we can start sending ASCII commands
''       to the transceiver. The following is a list of ASCII commands which will change various parameters in the XBEE_PRO transceiver:
''                              ASCII command:                 Purpose
''                               ATNI EK60Cxxx          Change the XBEE_PRO node identifier (NI).....
''                               ATWR                   Save parameter changes to XBEE_PRO non-volatile RAM.....
''                               ATCN                   Exit command mode and resume listening on wireless link...
''
''        Note: The XBee/XBee-PRO OEM RF Modules manual contains a list of AT commands for the wireless transceiver.
''
'' Example of XBee_Pro transceiver and Parallax Microprocessor interaction:
''        Parallax:             mcuSerial[ZIGBEE].str(string("+++")) --->microprocessor sends +++ command sequence.
''
''        ZIGBEE:               Responds with prompt string "OK"<CR><LF>
''
''        Parallax:             mcuSerial[ZIGBEE].RxStr(@prompt) --->Microprocessor looks for ZIGBEE command prompt...
''
''        Parallax:             mcuSerial[ZIGBEE].str(string("ATNI ",@cSerNum,13,10) --->Commands ZIGBEE to change its node ID...
''
''        ZIGBEE:               Responds with prompt string "OK"<CR><LF>
''
''        Parallax:             mcuSerial[ZIGBEE].str(string("ATWR",13,10)) ---> Microprocessor tells ZIGBEE to save its NI..
''
''        ZIGBEE:               Responds with prompt string "OK"<CR><LF>
''
''
  Delay_MS := 500
  repeat
    cmd := program_Menu
    case cmd
      1:                                                'Change Serial Number of EK60Cal device.

        repeat
          cNum := string("EK60C")                       'Standard beginning of serial number ID.
          bytefill(@cSerNum, 0, 15)
          bytemove(@cSerNum, cNum, strsize(cNum))
        
          mcuSerial[RS232].str(string("Enter device Serial Number and press ENTER:"))
          mcuSerial[RS232].str(string(13,10))
          mcuSerial[RS232].str(string("Note: Number should be between 1 and 999."))
          mcuSerial[RS232].str(string(13,10))
          mcuSerial[RS232].str(string(">>"))
          mcuSerial[RS232].rxflush                      'Flush the receive buffer...
          mcuSerial[RS232].RxStr(@cData)                'Get the data from the PC.

          dData := StrToFloat(@cData)                   'Convert string DATA to a decimal..
          check_Data := f.FTrunc(dData)                 'Convert decimal value into an integer value.

          if check_Data => 1 AND check_Data =< 999
        
                cData := fstr.FloatToFormat(dData, 3, 0, "0")
        
                bytemove(@cSerNum + strsize(@cSerNum), cData, strsize(cData)+1) 'Append number to "EK60C"
                numLength := strsize(@cSerNum)
                
'----------------------------- Write Serial Number Length to EEPROM. -----------------------------
                ifnot writeEEPROM(i2cSCL, EEPROM_ADDR, lenAddr, oneByte, numLength)
                  mcuSerial[RS232].str(string("Error Writing SerNum Length to EEPROM."))
                  mcuSerial[RS232].str(string(13,10))

'----------------------------- Write Actual Serial Number to EEPROM. -----------------------------
                repeat x from 0 to numLength-1
                  writeEEPROM(i2cSCL, EEPROM_ADDR, serAddr+x, oneByte, cSerNum[x])
                  waitcnt(clkfreq / 10 + cnt)           'Wait for 100 milliseconds.


'----------------------------- Change Node ID (NI) of ZIGBEE Transceiver. -----------------------------

                mcuSerial[ZIGBEE].rxflush                                       'Flush the receive buffer...
                mcuSerial[ZIGBEE].str(string("+++"))                            'Set ZIGBEE to command mode..
                mcuSerial[ZIGBEE].RxStrTime(10_000,@cData)                      'Get the "OK" prompt from the ZIGBEE.
                mcuSerial[RS232].str(string("ZigBee in command mode: "))
                mcuSerial[RS232].str(@cData)
                mcuSerial[RS232].str(string(13,10))

                mcuSerial[ZIGBEE].str(string("ATNI "))                          'Change the node identifier NI to the
                                                                                'Serial Number of the EK60 calibration
                                                                                'system.
                mcuSerial[ZIGBEE].str(@cSerNum)
                mcuSerial[ZIGBEE].str(string(13,10))
                mcuSerial[ZIGBEE].RxStrTime(10_000,@cData)                      'Get the "OK" prompt from the ZIGBEE.
                mcuSerial[RS232].str(string("Node ID changed: "))
                mcuSerial[RS232].str(@cData)
                mcuSerial[RS232].str(string(13,10))

                mcuSerial[ZIGBEE].str(string("ATWR"))                           'Write NI to the nonvolatile RAM on transceiver.
                mcuSerial[ZIGBEE].str(string(13,10))
                mcuSerial[ZIGBEE].RxStrTime(10_000,@cData)                      'Get the "OK" prompt from the ZIGBEE.
                mcuSerial[RS232].str(string("Node ID written to RAM: "))
                mcuSerial[RS232].str(@cData)
                mcuSerial[RS232].str(string(13,10))

                mcuSerial[ZIGBEE].str(string("ATCN"))                           'Exit Command Mode.
                mcuSerial[ZIGBEE].str(string(13,10))
                mcuSerial[ZIGBEE].RxStrTime(10_000,@cData)                      'Get the "OK" prompt from the ZIGBEE.
                mcuSerial[RS232].str(string("Exiting Command Mode: "))
                mcuSerial[RS232].str(@cData)
                mcuSerial[RS232].str(string(13,10))

'----------------------------- Tell operator that the changes has been accomplished. -----------------------------
                mcuSerial[RS232].str(string("Serial Number changed to: "))
                mcuSerial[RS232].str(@cSerNum)
                mcuSerial[RS232].str(string(13,10))
                quit
          else
                mcuSerial[RS232].str(string("Number was not between 1 and 999. "))
                mcuSerial[RS232].str(string(13,10))
                mcuSerial[RS232].str(string("Try again.......... "))
                mcuSerial[RS232].str(string(13,10))
                
      2:
        quit                                            ' Exit CASE statement and return...

      OTHER:
        mcuSerial[RS232].str(string("Invalid Menu Item........."))
        mcuSerial[RS232].str(string("Enter only numbers 1 to 2."))
        mcuSerial[RS232].str(string(13,10))

  return
 
PUB  program_Menu : rCmd 
''    This procedure will output a menu to the RS-232 port to allow the operator to program
'' the the ZigBee Wireless Transceiver as well as the Parallax Microcontroller settings.

  mcuSerial[RS232].str(string("-------------------------------------------------------"))
  mcuSerial[RS232].str(string(13,10))
  mcuSerial[RS232].str(string("1: Modify EchoCAL serial number."))
  mcuSerial[RS232].str(string(13,10))
  mcuSerial[RS232].str(string("2: Quit Menu and return."))
  mcuSerial[RS232].str(string(13,10))
  mcuSerial[RS232].str(string("-------------------------------------------------------"))
  mcuSerial[RS232].str(string(13,10))
  mcuSerial[RS232].str(string("Enter number and press return key."))
  mcuSerial[RS232].str(string(13,10))
  mcuSerial[RS232].str(string("EchoCAL>>"))

  rCmd := mcuSerial[RS232].rxHex                               ' Wait for a command from the user...
  mcuSerial[RS232].rxflush                                     ' Flush the receive buffer...
  
  return
 
PUB  handle_Ping | x
''    This procedure will let the PC know that it is up and running...

  Delay_MS := 500

  mcuSerial[RS232].str(string("$"))                     'Output PING string to PC.
  mcuSerial[RS232].str(@cSerNum)                          '
  mcuSerial[RS232].str(string(" operational."))
  mcuSerial[RS232].str(string(13,10))

  return
 

PUB readEEPROM(pinSCL, devSel, addrReg, bit_Count) : i2cData
''  This procedure will read a certain number of bytes depending on
'' what the value of "bit_Count" is.
''        bit_Count = 8  -> Read only a byte of data.
''        bit_Count = 16 -> Read a "word" of data.
''        bit_Count = 32 -> Read a "long word" of data.

  case bit_Count
    8:  ' Read a BYTE of data from EEPROM...
      i2cData := base_I2C.ReadByte(pinSCL, devSel, addrReg)
    16: ' Read a WORD of data from EEPROM...
      i2cData := base_I2C.ReadWord(pinSCL, devSel, addrReg)
    32: ' Read a LONG of data from EEPROM...
      i2cData := base_I2C.ReadLong(pinSCL, devSel, addrReg)

  return i2cData

PUB writeEEPROM(pinSCL, devSel, addrReg, bit_Count, i2cData) : write_OK | startTime
''  This procedure will write a certain number of bytes depending on
'' what the value of "bit_Count" is.
''        bit_Count = 8  -> Write only a byte of data.
''        bit_Count = 16 -> Write a "word" of data.
''        bit_Count = 32 -> Write a "long word" of data.
''
'' Local variable "startTime" is used as a delay to allow EEPROM time
'' to finish writing data. If the delay time gets longer than 1/10 second,
'' we will abort the write procedure...

  write_OK := TRUE
  case bit_Count
    8:  ' Read a BYTE of data from EEPROM...
      base_I2C.WriteByte(pinSCL, devSel, addrReg, i2cData)
    16: ' Read a WORD of data from EEPROM...
      base_I2C.WriteWord(pinSCL, devSel, addrReg, i2cData)
    32: ' Read a LONG of data from EEPROM...
      base_I2C.WriteLong(pinSCL, devSel, addrReg, i2cData)

  startTime := cnt 'Get current clock time...
  repeat while base_I2C.WriteWait(pinSCL, devSel, addrReg)
    if cnt - startTime > clkfreq / 10
      write_OK := FALSE  ' Waited more that 1/10 second for write to finish.  Not good!

  return

PRI StrToFloat(strptr) : floatnum | int, exp, sign
'
'  This procedure will convert a string to a floating point number...
'
  int := exp := sign := 0                               'Initialize variables for integer, decimal, and sign flags...

  repeat strsize(strptr)

    case byte[strptr]
      "-":
        sign~~
        
      ".":
        exp := 1

      "0".."9":
        int := int*10 + byte[strptr] -"0"
          if exp
              exp++                                     'Count decimal places...
      other:
        quit
    strptr++                                            'Increment pointer to next character in the string..

  if sign
    int := -int
  floatnum := f.FFloat(int)
  if exp
    repeat exp-1
      floatnum := f.FDiv(floatnum, 10.0)                'Adjust floatingpoint number for decimal place..
      
  return

DAT

             