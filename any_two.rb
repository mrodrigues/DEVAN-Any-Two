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

  def interval
    @interval ||= Shift.new(start_time, end_time)
  end

  private
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

  attr_reader :points, :e1, :e2

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
  def label; "(#{@e1.name}, #{@e2.name})"; end
  def unique_a; single_points_for(@e1.name); end
  def unique_b; single_points_for(@e2.name); end
  def any_two; agreements.count / points.count.to_f; end

  def print_result
    puts "============ #{label} ==============="
    puts "Any-two: #{any_two}"
    puts "Agreements: #{agreements.count}"
    puts "Disagreements: #{disagreements.count}"
    puts "Unique #{@e1.name}: #{single_points_for(@e1.name).count}"
    puts "Unique #{@e2.name}: #{single_points_for(@e2.name).count}"
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

LABELS = ('A'..'Z').to_a
data = Dir["#{File.dirname(__FILE__)}/data/*.csv"].each_with_index.map {|file, i| [CSV.read(file), LABELS[i]] }

evaluations = []
data.each {|file, name| evaluations << Evaluation.new(file, name, 4) }

results = []
evaluations.combination(2) { |e1, e2| results << AnyTwo.new(e1, e2) }
results.each(&:print_result)

filename = "results.csv"
CSV.open(filename, "wb") do |csv|
  csv << ["Evaluations", "Any-Two", "Agreements", "Disagreements", "Unique A", "Unique B"]
  results.each do |result|
    csv << [
      result.label,
      result.any_two,
      result.agreements.count,
      result.disagreements.count,
      result.unique_a.count,
      result.unique_b.count
    ]
  end
end

puts "Results written to #{filename}"

all_agreements = []
results.each do |result|
  all_agreements += result.agreements

  start_str = "Start time - %s"
  end_str = "End time - %s"
  e1, e2 = result.e1, result.e2
  filename = "agreements_#{e1.name}-#{e2.name}.csv"
  CSV.open(filename, "wb") do |csv|
    csv << [
      "CODE",
      start_str % e1.name,
      end_str   % e1.name,
      start_str % e2.name,
      end_str   % e2.name
    ]
    result.agreements.each do |agreement|
      b1, b2 = agreement.b1, agreement.b2
      if b1.evaluator != e1.name
        b1, b2 = b2, b1
      end
      csv << [b1.codes.join("/"), b1.start_time, b1.end_time, b2.start_time, b2.end_time]
    end
  end

  puts "Agreements for #{e1.name} and #{e2.name} written to #{filename}"
end

all_agreements = all_agreements.map {|p| p.b1.interval.duration < p.b2.interval.duration ? p.b1 : p.b2 }
all_agreements.sort_by! {|b| b.start_time }

filename = "all_agreements.csv"
CSV.open(filename, "wb") do |csv|
  csv << [
    "CODE",
    "Start time",
    "End time"
  ]

  all_agreements.each do |b|
    csv << [b.codes.join("/"), b.start_time, b.end_time]
  end
end

puts "All agreements written to #{filename}"
