require 'tod'
require 'csv'
require 'set'

class Breakdown < Struct.new(:codes, :start_time, :end_time, :evaluator)

  VALID_CODES = %w(ACE ACP ACX AJU ANT CON IMP PAS PEX PFC PPR RAN STP TED)

  def initialize(codes, start_time, end_time, evaluator)
    codes = codes.split('/').map(&:strip)
    super(codes, start_time, end_time, evaluator)
    validate_codes!
  end

  def include?(breakdown)
    interval.include?(breakdown.start_time) ||
      interval.include?(breakdown.end_time)
  end

  def eql?(b)
    return false unless b
    codes == b.codes &&
      start_time == b.start_time &&
      end_time == b.end_time
  end

  def to_s
    "[%s] %s - %s" % [codes.join('/'), start_time, end_time]
  end

  private
    def interval
      @interval ||= Shift.new(start_time, end_time)
    end

    def validate_codes!
      codes.each { |code| raise "Code not valid: #{code}" unless VALID_CODES.include?(code) }
    end
end

class Evaluation
  attr_reader :breakdowns, :name

  def initialize(data, name, threshold = 4)
    @name = name
    @breakdowns = []
    data.each do |d|
      next if d[0].nil?                   # not a breakdown
      d[2] = d[1] if d[2].nil?            # convert to interval
      d[1] = parse_time(d[1], -threshold) # add threshold
      d[2] = parse_time(d[2], +threshold) # add threshold
      @breakdowns << Breakdown.new(*d[0..2], name)
    end
  end

  private
    def parse_time(time, offset)
      time = TimeOfDay.parse(time.rjust(8, '00:00:00'))
      if time.to_i + offset < 0
        offset = -time.to_i
      end
      time + offset
    end
end

class Point < Struct.new(:b1, :b2)

  def result
    return :single_point if b2.nil?
    return :agreement if b1.codes == b2.codes
    return :disagreement
  end

  def single_point?; result == :single_point; end
  def agreement?; result == :agreement; end
  def disagreement?; result == :disagreement; end

  def eql?(o)
    (b1.eql?(o.b1) && b2.eql?(o.b2)) ||
    (b1.eql?(o.b2) && b2.eql?(o.b1))
  end

  def hash; 0; end

  def to_s
    '-' * 25 + "\n#{b1}\n#{b2}"
  end

  def self.points_from(b1, b2)
    b2_codes = b2.nil? ? [nil] : b2.codes

    result = []

    # For every pair of codes at the point
    b1.codes.product(b2_codes).each do |codes|
      breakdown1 = Breakdown.new(codes[0], b1.start_time, b1.end_time, b1.evaluator)
      breakdown2 = if codes[1]
                     Breakdown.new(codes[1], b2.start_time, b2.end_time, b2.evaluator)
                   else
                     nil
                   end
      result << Point.new(breakdown1, breakdown2)
    end

    result
  end
end

class AnyTwo

  attr_reader :points

  def initialize(e1, e2)
    @e1, @e2 = e1, e2
    @single_points = { e1.name => [], e2.name => [] }
    @points = Set.new
    compare!
  end

  def single_points; points.select(&:single_point?); end
  def agreements; points.select(&:agreement?); end
  def disagreements; points.select(&:disagreement?); end
  def single_points_for(name); @single_points[name]; end

  def print_result
    puts "============ (#{@e1.name}, #{@e2.name}) ==============="
    puts "any-two: #{agreements.count / points.count.to_f}"
    puts "agreements: #{agreements.count}"
    puts "single_points: #{single_points.count}"
    puts "disagreements: #{disagreements.count}"
    puts "total points: #{points.count}"
    puts "breakdowns for #{@e1.name}: #{@e1.breakdowns.count}"
    puts "single points for #{@e1.name}: #{single_points_for(@e1.name).count}"
    puts "breakdowns from #{@e2.name}: #{@e2.breakdowns.count}"
    puts "single points for #{@e2.name}: #{single_points_for(@e2.name).count}"
    puts
  end

  private
    def compare!
      compare_between!(@e1.breakdowns, @e2.breakdowns)
      compare_between!(@e2.breakdowns, @e1.breakdowns)
    end

    def compare_between!(e1, e2)
      e1.each do |b1|
        matches = []

        e2.each do |b2|
          if b1.include?(b2)
            matches += Point.points_from(b1, b2)
          end
        end

        if matches.empty?
          matches = Point.points_from(b1, nil)
          @single_points[b1.evaluator] += matches
        end

        @points += matches
      end
    end
end

data = Dir["#{File.dirname(__FILE__)}/data/*.csv"].map {|file| [CSV.read(file), file] }

evaluations = []
data.each {|file, name| evaluations << Evaluation.new(file, name, 4) }

results = []
evaluations.combination(2) { |e1, e2| results << AnyTwo.new(e1, e2) }
results.each(&:print_result)
