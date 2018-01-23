port module Main exposing (..)

import Json.Decode exposing (..)
import Platform exposing (..)
import Bitwise exposing (..)
import Time exposing (..)
import List exposing (..)


{- Elm-Arduino-GBA-Multiboot-Cable! (by Andre Taulien)

   Some trivia about the Gameboy Advance:

     - The BIOS of each GBA has a section, which allows a small portion of
     - arbitrary code (256K) to be downloaded through the Link-Port,
     - called "multiboot".

   About the GBAs Link-Cable:

     - I found this information to be hard to find online, so here it is again:
     - The protocol used by the GBA (all gameboys, really) to send data over the
     - Link-Cable is just your usual SPI! Yes, the industry-standard SPI. I've
     - come across too many websites describing what the protocol looks like as
     - "some weird 16-bit"-protocol, so "let's roll our own solution for that".
     - Well, since SPI is widely used, there are libraries for it. Almost every
     - microcontroller supports it today. Please don't roll your own.
     - To be more exact on the variant of SPI, here are settings that worked for me:
         - SPI-Mode: 3
         - Speed: 256000hz
         - 32-Bit transfers

   Here is an overview of the multiboot-process:

   1.  Search for the gameboy until it answers with a specific number
   2.  When found and configured for multibooting, transfer the ROM-header
   3.  Exchange some information regarding encryption
   4.  Send encrypted rest of the ROM-file
   5.  Exchange CRCs

   For a detailed description, you can go here:

     - <http://problemkaputt.de/gbatek.htm#biosfunctions> (Multiboot Transfer Protocol)

   This elm-program talks to a connected Arduino over a serial port, which packs
   the data and sends it over to a connected Gameboy-Advance.

-}
{- ------------------------------INPUT-PORTS---------------------------------- -}


{-| Called when the arduino sent us a message
-}
port port_on_remote_command : (Int -> msg) -> Sub msg


{-| Called when a file loaded using port_read_file_contents is ready
-}
port port_on_file_contents_loaded : (List Byte -> msg) -> Sub msg


{-| Called when nodejs has some commandline-arguments for us...
-}
port port_on_program_config : (List String -> msg) -> Sub msg



{- -----------------------------OUTPUT-PORTS---------------------------------- -}


{-| Writes data to the serialport connected to the arduino
-}
port port_write_serial : List Byte -> Cmd msg


{-| Requests to read a file from dist. Calls port_on_file_contents_loaded
when all data is loaded.
-}
port port_read_file_contents : String -> Cmd msg


{-| Writes data to the nodejs-console
-}
port port_write_console : String -> Cmd msg


{-| Writes data to the nodejs-console, but straight to stdout, saving us
from nodejs putting a newline behind our message.
-}
port port_write_stdout : String -> Cmd msg


{-| Initializes the serial-port used to talk to the arduino
-}
port port_initalize_serial_port : String -> Cmd msg


type Msg
    = OnStateEntered
    | OnProgramConfig (List String) -- Serial-port, rom-file
    | OnCommandFromArduino Int
    | OnFileContentsLoaded (List Byte)
    | OnFileLoadFailed String -- reason


type State
    = LoadRom
    | WaitForArduino
    | TransferRom
    | Done


type alias Byte =
    Int


type alias Model =
    { state : State
    , rom : Result String (List Byte)
    , serialport : Maybe String
    , romfile : Maybe String
    }


{-| Loads the ROM from a file.
-}
stateLoadRom : Msg -> Model -> ( Model, Cmd Msg )
stateLoadRom msg model =
    case msg of
        -- Commandline arguments arrived!
        OnProgramConfig args ->
            case args of
                serialport :: romfile :: [] ->
                    ( { model
                        | serialport = Just serialport
                        , romfile = Just romfile
                      }
                    , port_read_file_contents romfile
                    )

                _ ->
                    ( model, port_write_console "Invalid commandline-args..." )

        -- ROM-File contents arrived!
        OnFileContentsLoaded rom ->
            case model.serialport of
                Nothing ->
                    ( model
                    , port_write_console "No serialport set!"
                    )

                Just serialport ->
                    ( { model
                        | state = WaitForArduino
                        , rom = Ok rom
                      }
                    , Cmd.batch
                        [ port_write_console ("Loaded ROM-File (" ++ (toString (length rom)) ++ " bytes)")
                        , port_write_console "Waiting for arduino to boot now..."
                        , port_initalize_serial_port serialport
                        ]
                    )

        OnFileLoadFailed reason ->
            ( { model | rom = Err reason }
            , port_write_console ("Failed to read ROM-File: " ++ reason)
            )

        _ ->
            ( model, Cmd.none )


{-| Arduinos have the weird tendency to reboot when something connects to
their serial-port. The common workaround is to send a command over serial when
the arduino has finally rebooted, so we can continue.

The first actual transfer is:

1.  The size of the ROM (4-Bytes Little Endian)
2.  The ROM-Header (0xC0 Bytes)

That can be sent in one go. The next command from the arduino will indicate
that the rest of the ROM can now be sent, so go and wait for that afterwards!

-}
stateWaitForArduino : Msg -> Model -> ( Model, Cmd Msg )
stateWaitForArduino msg model =
    case msg of
        OnCommandFromArduino cmd ->
            case cmd of
                -- Arduino booted
                0x01 ->
                    case model.rom of
                        Err _ ->
                            ( model
                            , port_write_console "Can't send header, no ROM-Data available!"
                            )

                        Ok data ->
                            ( { model | state = TransferRom, rom = Ok (List.drop 0xC0 data) }
                            , Cmd.batch
                                [ port_write_console "Arduino connected!"
                                , Cmd.batch
                                    [ port_write_serial ((int32ToByteList (length data)) ++ (List.take 0xC0 data))
                                    , port_write_console "Sending header..."
                                    ]
                                ]
                            )

                _ ->
                    ( model, port_write_console ("Invalid command: " ++ (toString cmd)) )

        _ ->
            ( model, Cmd.none )


{-| The Arduino will now exchange some information about the encryption with
the gameboy. Afterwards, it will send a command indicating that it is ready
to receive the rest of the ROM.

Then we send our ROM-File to the arduino. In small pieces, so the arduinos
serial-input-buffer doesn't run full. I'm not exactly sure how many bytes fit in
there, so one could probably up the block-size and still be fine...

-}
stateTransferRom : Msg -> Model -> ( Model, Cmd Msg )
stateTransferRom msg model =
    case msg of
        OnCommandFromArduino cmd ->
            case cmd of
                -- Write Done
                0x03 ->
                    case model.rom of
                        Err _ ->
                            ( model, port_write_console "Can't send block, no ROM-Data available!" )

                        Ok [] ->
                            ( { model | state = Done }
                            , port_write_console "Transmission complete!"
                            )

                        Ok data ->
                            ( { model | rom = Ok (List.drop 32 data) }
                            , Cmd.batch
                                [ port_write_serial (List.take 32 data)
                                ]
                            )

                _ ->
                    ( model, port_write_console ("Invalid command: " ++ (toString cmd)) )

        _ ->
            ( model, Cmd.none )


{-| All done, let's hope this worked!
-}
stateDone : Msg -> Model -> ( Model, Cmd Msg )
stateDone msg model =
    ( model, Cmd.none )


int32ToByteList : Int -> List Int
int32ToByteList v =
    [ and 0xFF v
    , and (shiftRightBy 8 v) 0xFF
    , and (shiftRightBy 16 v) 0xFF
    , and (shiftRightBy 24 v) 0xFF
    ]



{- -------------------------------------------------------------------------- -}


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case model.state of
        LoadRom ->
            stateLoadRom msg model

        WaitForArduino ->
            stateWaitForArduino msg model

        TransferRom ->
            stateTransferRom msg model

        Done ->
            stateDone msg model


init : ( Model, Cmd Msg )
init =
    ( { state = LoadRom
      , rom = Err "ROM not loaded"
      , serialport = Nothing
      , romfile = Nothing
      }
    , Cmd.none
    )


subscriptions : Model -> Sub Msg
subscriptions model =
    case model.state of
        LoadRom ->
            Sub.batch
                [ port_on_program_config OnProgramConfig
                , port_on_file_contents_loaded OnFileContentsLoaded
                ]

        WaitForArduino ->
            Sub.batch
                [ port_on_remote_command OnCommandFromArduino
                ]

        TransferRom ->
            Sub.batch
                [ port_on_remote_command OnCommandFromArduino
                ]

        Done ->
            Sub.none


main =
    Platform.program
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
