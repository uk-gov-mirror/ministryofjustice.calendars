class Calendar

  REPOSITORY_PATH = Rails.env.test? ? "test/fixtures/data" : "lib/data"

  class CalendarNotFound < StandardError
  end

  def self.find(slug)
    json_file = Rails.root.join(REPOSITORY_PATH, "#{slug}.json")
    if File.exists?(json_file)
      data = JSON.parse(File.read(json_file))
      self.new(slug, data)
    else
      raise CalendarNotFound
    end
  end

  def self.all_slugs
    slugs = []
    Dir.glob("#{REPOSITORY_PATH}/*.json").each do |path|
      slugs << path.gsub(REPOSITORY_PATH, '').gsub('.json','')
    end
    slugs
  end

  class Repository
    def initialize(name)
      @json_path = Rails.root.join(Calendar::REPOSITORY_PATH, name + ".json")

      unless File.exists? @json_path
        raise Calendar::CalendarNotFound.new( @json_path )
      end
    end

    def need_id
      parsed_data[:need_id]
    end

    def parsed_data
      @parsed_data ||= JSON.parse(File.read(@json_path)).symbolize_keys
    rescue
      false
    end

    def all_grouped_by_division
      Hash[parsed_data[:divisions].map { |division, by_year|
        calendars_for_division = {
          division:  division,
          calendars: Hash[by_year.sort.map { |year, events|
            next unless year =~ /\A\d{4}\z/
            calendar = Calendar.new('', year: year, division: division, events:
              events.map { |event|
                Event.new(
                  title: event['title'],
                  date:  Date.strptime(event['date'], "%d/%m/%Y"),
                  notes: event['notes'],
                  bunting: event['bunting'] || "false"
                )
              }
            )
            [calendar.year, calendar]
          }.compact]
        }
        calendars_for_division[:whole_calendar] = Calendar.combine_inside_division calendars_for_division[:calendars]
        [division, calendars_for_division]
      }]
    end

    def find_by_division_and_year(division, year)
      calendar = all_grouped_by_division[division][:calendars][year]

      unless calendar
        raise Calendar::CalendarNotFound.new( division, year )
      else
        calendar
      end
    end

    def combined_calendar_for_division(division)
      calendar = all_grouped_by_division[division]

      if calendar
        wc = calendar[:whole_calendar]
      else
        raise Calendar::CalendarNotFound.new( division )
      end
    end
  end

  attr_reader :slug
  alias :to_param :slug

  attr_accessor :year, :events

  def initialize(slug, data = {})
    @slug = slug
    @data = data
    self.year     = data[:year]
    self.events   = data[:events] || []
  end

  def divisions
    @divisions ||= @data["divisions"].map {|slug, data| Division.new(slug, data) }
  end

  def division(slug)
    div = divisions.find {|d| d.slug == slug }
    raise CalendarNotFound unless div
    div
  end

  def as_json(options = nil)
    # TODO: review this representation
    # This is kinda messy because the top-level JSON representation is inconsistent
    # with the lower level representations
    divisions.each_with_object({}) do |division, hash|
      hash[division.slug] = {
        "division" => division.slug,
        "calendars" => division.years.each_with_object({}) do |year, years|
          years[year.to_s] = year
        end
      }
    end
  end

  def upcoming_event
    @events.select{|e| e.date > Date.today-1.day }.first
  end

  def event_today?
    upcoming_event.date == Date.today
  end

  def bunting?
    upcoming_event.bunting == "true" && self.event_today?
  end

  def formatted_division(str = division)
    case str
    when 'england-and-wales'
      "England and Wales"
    when 'scotland'
      "Scotland"
    when 'northern-ireland'
      "Northern Ireland"
    end
  end

  def to_ics
    output = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"
    output << "PRODID:-//uk.gov/GOVUK calendars//EN\r\n"
    output << "CALSCALE:GREGORIAN\r\n"
    self.events.each do |event|
      output << "BEGIN:VEVENT\r\n"
      output << "DTEND;VALUE=DATE:#{ event.date.strftime("%Y%m%d") }\r\n"
      output << "DTSTART;VALUE=DATE:#{ event.date.strftime("%Y%m%d") }\r\n"
      output << "SUMMARY:#{ event.title }\r\n"
      output << "END:VEVENT\r\n"
    end
    output << "END:VCALENDAR\r\n"
  end

  def self.combine(calendars, division)
    raise CalendarNotFound unless calendars[division]
    self.combine_inside_division calendars[division][:calendars]
  end

  def self.combine_inside_division(calendars)
    info = calendars.first[1]

    combined_calendar = Calendar.new('',:division => info.division)
    calendars.each do |year, cal|
      combined_calendar.events += cal.events
    end
    combined_calendar.format_output
  end

  def format_output
    remove_instance_variable(:@year)
    self
  end
end
