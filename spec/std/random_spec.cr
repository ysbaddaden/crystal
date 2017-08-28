require "spec"

private class TestRNG(T)
  include Random

  def initialize(@data : Array(T))
    @i = 0
  end

  def next_u : T
    i = @i
    @i = (i + 1) % @data.size
    @data[i]
  end

  def reset
    @i = 0
  end
end

private RNG_DATA_8  = [234u8, 153u8, 0u8, 0u8, 127u8, 128u8, 255u8, 255u8]
private RNG_DATA_32 = [31541451u32, 0u32, 1u32, 234u32, 342475672u32, 863u32, 0xffffffffu32, 50967465u32]
private RNG_DATA_64 = [148763248732657823u64, 18446744073709551615u64, 0u64,
                       32456325635673576u64, 2456245614625u64, 32452456246u64, 3956529762u64,
                       9823674982364u64, 234253464546456u64, 14345435645646u64]

describe "Random" do
  it "limited number" do
    rand(1).should eq(0)

    x = rand(2)
    x.should be >= 0
    x.should be < 2

    # issue 3350
    5.times do
      rand(Int64::MAX).should be >= 0
    end
  end

  it "float number" do
    x = rand
    x.should be >= 0
    x.should be <= 1
  end

  it "limited float number" do
    x = rand(3.5)
    x.should be >= 0
    x.should be < 3.5
  end

  it "raises on invalid number" do
    expect_raises ArgumentError, "Invalid bound for rand: 0" do
      rand(0)
    end
  end

  it "does with inclusive range" do
    [1..1, 1..3, 0u8..255u8, -1..1, Int64::MIN..7i64,
     -7i64..Int64::MAX, 0u64..0u64].each do |range|
      x = rand(range)
      x.should be >= range.begin
      x.should be <= range.end
    end
  end

  it "does with exclusive range" do
    [1...2, 1...4, 0u8...255u8, -1...1, Int64::MIN...7i64,
     -7i64...Int64::MAX, -1i8...0i8].each do |range|
      x = rand(range)
      x.should be >= range.begin
      x.should be < range.end
    end
  end

  it "does with inclusive range of floats" do
    rand(1.0..1.0).should eq(1.0)
    x = rand(1.8..3.2)
    x.should be >= 1.8
    x.should be <= 3.2
  end

  it "does with exclusive range of floats" do
    x = rand(1.8...3.3)
    x.should be >= 1.8
    x.should be < 3.3
  end

  it "raises on invalid range" do
    expect_raises ArgumentError, "Invalid range for rand: 1...1" do
      rand(1...1)
    end
    expect_raises ArgumentError, "Invalid range for rand: 1..0" do
      rand(1..0)
    end
    expect_raises ArgumentError, "Invalid range for rand: 1.0...1.0" do
      rand(1.0...1.0)
    end
    expect_raises ArgumentError, "Invalid range for rand: 1.0..0.0" do
      rand(1.0..0.0)
    end
  end

  it "allows creating a new default random" do
    rand = Random.new
    value = rand.rand
    (0 <= value < 1).should be_true
  end

  it "allows creating a new default random with a seed" do
    values = Array.new(2) do
      rand = Random.new(1234)
      {rand.rand, rand.rand(0xffffffffffffffff), rand.rand(2), rand.rand(-5i8..5i8)}
    end

    values[0].should eq values[1]
  end

  it "gets a random bool" do
    Random::DEFAULT.next_bool.should be_a(Bool)
  end

  it "generates by accumulation" do
    rng = TestRNG.new([234u8, 153u8, 0u8, 0u8, 127u8, 128u8, 255u8, 255u8])
    rng.rand(65536).should eq 60057    # 234*0x100 + 153
    rng.rand(60000).should eq 0        # 0*0x100 + 0
    rng.rand(30000).should eq 2640     # (127*0x100 + 128) % 30000
    rng.rand(65535u16).should eq 60057 # 255*0x100 + 255 [skip]-> 234*0x100 + 153
    rng.reset
    rng.rand(65537).should eq 38934 # (234*0x10000 + 153*0x100 + 0) % 65537
    rng.reset
    rng.rand(32768u16).should eq 27289 # (234*0x100 + 153) % 32768
  end

  it "generates by truncation" do
    rng = TestRNG.new([31541451u32, 0u32, 1u32, 234u32, 342475672u32])
    rng.rand(1).should eq 0
    rng.rand(10).should eq 0
    rng.rand(2).should eq 1
    rng.rand(256u64).should eq 234
    rng.rand(255u8).should eq 217   # 342475672 % 255
    rng.rand(65536).should eq 18635 # 31541451 % 65536
    rng = TestRNG.new([0xffffffffu32, 0u32])
    rng.rand(0x7fffffff).should eq 0
  end

  it "generates full-range" do
    rng = TestRNG.new(RNG_DATA_64)
    RNG_DATA_64.each do |a|
      rng.rand(UInt64::MIN..UInt64::MAX).should eq a
    end
  end

  it "generates full-range by accumulation" do
    rng = TestRNG.new(RNG_DATA_8)
    RNG_DATA_8.each_slice(2) do |(a, b)|
      expected = a.to_u16 * 0x100u16 + b.to_u16
      rng.rand(UInt16::MIN..UInt16::MAX).should eq expected
    end
  end

  it "generates full-range by truncation" do
    rng = TestRNG.new(RNG_DATA_32)
    RNG_DATA_32.each do |a|
      expected = a % 0x10000
      rng.rand(UInt16::MIN..UInt16::MAX).should eq expected
    end
  end

  it "generates full-range by negation" do
    rng = TestRNG.new(RNG_DATA_8)
    RNG_DATA_8.each do |a|
      expected = a.to_i
      expected -= 0x100 if a >= 0x80
      rng.rand(Int8::MIN..Int8::MAX).should eq expected
    end
  end

  describe "random_bytes" do
    it "gets random bytes with default number of digits" do
      bytes = TestRNG.new(RNG_DATA_32).random_bytes
      bytes.size.should eq(16)
    end

    it "gets random bytes with requested number of digits" do
      bytes = TestRNG.new(RNG_DATA_32).random_bytes(50)
      bytes.size.should eq(50)
    end

    it "fully fills a large buffer" do
      bytes = TestRNG.new(RNG_DATA_32).random_bytes(10000)
      bytes[9990, 10].should_not eq(Bytes.new(10))
    end

    it "fills given buffer with random bytes" do
      bytes = Bytes.new(2000)
      TestRNG.new(RNG_DATA_32).random_bytes(bytes)
      bytes.size.should eq 2000
      bytes[1990, 10].should_not eq(Bytes.new(10))
    end
  end

  describe "base64" do
    it "gets base64 with default number of digits" do
      base64 = TestRNG.new(RNG_DATA_32).base64
      base64.size.should eq(24)
      base64.should_not match(/\n/)
    end

    it "gets base64 with requested number of digits" do
      base64 = TestRNG.new(RNG_DATA_32).base64(50)
      base64.size.should eq(68)
      base64.should_not match(/\n/)
    end
  end

  describe "urlsafe_base64" do
    it "gets urlsafe base64 with default number of digits" do
      base64 = TestRNG.new(RNG_DATA_32).urlsafe_base64
      (base64.size <= 24).should be_true
      base64.should_not match(/[\n+\/=]/)
    end

    it "gets urlsafe base64 with requested number of digits" do
      base64 = TestRNG.new(RNG_DATA_32).urlsafe_base64(50)
      (base64.size >= 24 && base64.size <= 68).should be_true
      base64.should_not match(/[\n+\/=]/)
    end

    it "keeps padding" do
      base64 = TestRNG.new(RNG_DATA_32).urlsafe_base64(padding: true)
      base64[-2..-1].should eq("==")
    end
  end

  describe "hex" do
    it "gets hex with default number of digits" do
      hex = TestRNG.new(RNG_DATA_32).hex
      hex.size.should eq(32)
      hex.each_char do |char|
        ('0' <= char <= '9' || 'a' <= char <= 'f').should be_true
      end
    end

    it "gets hex with requested number of digits" do
      hex = TestRNG.new(RNG_DATA_32).hex(50)
      hex.size.should eq(100)
      hex.each_char do |char|
        ('0' <= char <= '9' || 'a' <= char <= 'f').should be_true
      end
    end
  end

  describe "uuid" do
    it "gets uuid" do
      uuid = TestRNG.new(RNG_DATA_32).uuid
      uuid.should match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{4}[0-9a-f]{8}\Z/)
    end
  end
end
