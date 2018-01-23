/**
 * Multiboot-Loader for the GBA by Andre Taulien (2018)
 * 
 * This was quickly thrown together for university (we've all been there, right?), so sorry for the lack of documentation.
 * Besides, this project was about using the "elm"-language, so who cares about c?
 */

#include <SPI.h>


// http://problemkaputt.de/gbatek.htm (Multiboot Transfer Protocol)
//
//  Pin    SPI    GBA
//  -----------------
//  12     miso   SO
//  11     mosi   SI
//  10     sck    SC

const uint8_t COMMAND_STARTUP = 0x01;
const uint8_t COMMAND_WRITE_DONE = 0x03;

uint16_t answers[512];
uint16_t numAnswers = 0;


void setup()
{
  uint32_t r;

  pinMode(LED_BUILTIN, OUTPUT);

  Serial.begin(57600);

  Serial.setTimeout(-1);

  SPI.begin();
  SPI.beginTransaction (SPISettings (256000, MSBFIRST, SPI_MODE3));

  Serial.write(COMMAND_STARTUP);

  upload();

  while(1);
}


void loop() {


}


void receiveRomHeader(uint8_t* pTarget)
{
  for (int i = 0; i < 0xC0; i++)
  {
    pTarget[i] = serial_read8();
  }
}


void receiveRomLength(uint32_t* pTarget)
{
  *pTarget = serial_read32();
}


uint32_t serial_read32(void)
{
  uint32_t rx1 = serial_read8();
  uint32_t rx2 = serial_read8();
  uint32_t rx3 = serial_read8();
  uint32_t rx4 = serial_read8();

  return rx1 | (rx2 << 8) | (rx3 << 16) | (rx4 << 24);
}


uint8_t serial_read8(void)
{
  uint8_t rx;

  Serial.readBytes(&rx, 1);

  return (uint8_t)rx;
}


void serial_write16(uint16_t tx)
{
  Serial.write(tx & 0xFF);
  Serial.write(tx >> 8);
}


void serial_write32(uint32_t tx)
{
  serial_write16(tx & 0xFFFF);
  serial_write16(tx >> 16);
}


uint16_t spi_transmit_receive16(uint16_t tx16)
{
  uint16_t rx = SPI.transfer16(tx16);
  delayMicroseconds(36);
  //delayMicroseconds(10);

  return rx;
}


void spi_transmit16(uint16_t tx16)
{
  uint16_t rx = SPI.transfer16(tx16);
  delayMicroseconds(36);
  //delayMicroseconds(10);
}


uint32_t spi_transmit_receive32(uint32_t tx)
{
  uint32_t rx[4];

  rx[0] = SPI.transfer((tx >> 24) & 0xFF);
  rx[1] = SPI.transfer((tx >> 16) & 0xFF);
  rx[2] = SPI.transfer((tx >> 8) & 0xFF);
  rx[3] = SPI.transfer(tx & 0xFF);

  delayMicroseconds(36);
  //delayMicroseconds(10);

  return rx[3] | (rx[2] << 8) | (rx[1] << 16) | (rx[0] << 24);
}


void spi_transmit32(uint32_t tx)
{
  SPI.transfer((tx >> 24) & 0xFF);
  SPI.transfer((tx >> 16) & 0xFF);
  SPI.transfer((tx >> 8) & 0xFF);
  SPI.transfer(tx & 0xFF);

  delayMicroseconds(36);
  //delayMicroseconds(10);
}


void setLedEnabled(bool enabled)
{
  digitalWrite(LED_BUILTIN, enabled ? HIGH : LOW);
}


uint32_t WriteSPI32NoDebug(uint32_t w)
{
  return spi_transmit_receive32(w);
}


uint32_t WriteSPI32(uint32_t w, const char* msg)
{
  uint32_t r = WriteSPI32NoDebug(w);

  char buf[32];
  sprintf(buf, "0x%08x 0x%08x  ; ", r, w);
  Serial.print(buf);
  Serial.println(msg);
  return  r;
}


void WaitSPI32(uint32_t w, uint32_t comp, const char* msg)
{
  char buf[32];
  sprintf(buf, " 0x%08x\n", comp);
  Serial.print(msg);
  Serial.print(buf);
  
  uint32_t r;

  do
  {
    r = WriteSPI32NoDebug(w);

  } while(r != comp);
}

/**
 * Mostly taken from https://github.com/akkera102/gba_01_multiboot
 * Honestly, it's the best implementation I could find. Straight to the point, no bullshit, no crappy code.
 */
void upload(void)
{

  uint32_t fsize;
  receiveRomLength(&fsize);
  Serial.print("Received ROM-Size: "); Serial.println(fsize);

  uint8_t header[0xC0];
  receiveRomHeader(header);

  if(fsize > 0x40000)
  {
    Serial.println("Romfile too large!");
    return;
  }
  
  long fcnt = 0;

  uint32_t r, w, w2;
  uint32_t i, bit;


  WaitSPI32(0x00006202, 0x72026202, "Looking for GBA");

  r = WriteSPI32(0x00006202, "Found GBA");
  r = WriteSPI32(0x00006102, "Recognition OK");
  
  Serial.println("Send Header(NoDebug)");
  for(i=0; i<=0x5f; i++)
  {
    w = header[2*i];
    w = header[2*i+1] << 8 | w;
    fcnt += 2;

    r = WriteSPI32NoDebug(w);
  }

  r = WriteSPI32(0x00006200, "Transfer of header data complete");
  r = WriteSPI32(0x00006202, "Exchange master/slave info again");

  r = WriteSPI32(0x000063d1, "Send palette data");
  r = WriteSPI32(0x000063d1, "Send palette data, receive 0x73hh****");  

  uint32_t m = ((r & 0x00ff0000) >>  8) + 0xffff00d1;
  uint32_t h = ((r & 0x00ff0000) >> 16) + 0xf;

  r = WriteSPI32((((r >> 16) + 0xf) & 0xff) | 0x00006400, "Send handshake data");
  r = WriteSPI32((fsize - 0x190) / 4, "Send length info, receive seed 0x**cc****");

  uint32_t f = (((r & 0x00ff0000) >> 8) + h) | 0xffff0000;
  uint32_t c = 0x0000c387;

  //Serial.write(COMMAND_SUCCESS);
  Serial.println("Send encrypted data(NoDebug)");

  Serial.write(COMMAND_WRITE_DONE);
  
  uint32_t bytes_received = 0;
  while(fcnt < fsize)
  {
    
    if(bytes_received == 32)
    {
      Serial.write(COMMAND_WRITE_DONE);
      bytes_received = 0;
    }

    w = serial_read32();
    bytes_received += 4;
    
    if(fcnt % 0x800 == 0 || fcnt > 63488) 
    {
      Serial.print(fcnt); Serial.print("/"); Serial.println(fsize);
    }


    w2 = w;

    for(bit=0; bit<32; bit++)
    {
      if((c ^ w) & 0x01)
      {
        c = (c >> 1) ^ 0x0000c37b;
      }
      else
      {
        c = c >> 1;
      }

      w = w >> 1;
    }

    
    m = (0x6f646573 * m) + 1;
    WriteSPI32NoDebug(w2 ^ ((~(0x02000000 + fcnt)) + 1) ^m ^0x43202f2f);

    fcnt = fcnt + 4;
  }

  Serial.println("ROM sent! Doing checksum now...");

  for(bit=0; bit<32; bit++)
  {
    if((c ^ f) & 0x01)
    {
      c =( c >> 1) ^ 0x0000c37b;
    }
    else
    {
      c = c >> 1;
    }

    f = f >> 1;
  }

  WaitSPI32(0x00000065, 0x00750065, "Wait for GBA to respond with CRC");

  
  Serial.print("CRC: "); Serial.println(c, HEX);

  r = WriteSPI32(0x00000066, "GBA ready with CRC");
  r = WriteSPI32(c,          "Let's exchange CRC!");

  Serial.println("All done, let's hope this worked!");
}




