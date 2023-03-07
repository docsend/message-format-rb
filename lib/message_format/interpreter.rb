require 'twitter_cldr'

#
# Interpreter
#
# Turns this:
#  [ "You have ", [ "numBananas", "plural", 0, {
#       "=0": [ "no bananas" ],
#      "one": [ "a banana" ],
#    "other": [ [ '#' ], " bananas" ]
#  } ], " for sale." ]
#
# into this:
#  format({ numBananas:0 })
#  "You have no bananas for sale."
#
module MessageFormat
  class Interpreter

    def initialize ( options=nil )
      if options&.has_key?(:locale)
        @locale = options[:locale]
      else
        @locale = TwitterCldr.locale
      end

      if options&.has_key?(:raise_on_missing_params)
        @raise_on_missing_params = options[:raise_on_missing_params]
      else
        @raise_on_missing_params = false
      end
    end

    #
    # MissingParametersError
    #  Holds information about parameters that were accessed during interpretation but were not
    #  provided. Only raised if the `raise_on_missing_params` option is set to `true`.
    #
    #  Example:
    #  message = MessageFormat.new('Hello { place } and { player }!', 'en-US', raise_on_missing_params: true)
    #  formatted = message.format({ :place => 'World' }) # raises with "player" identified as a missing parameter
    #
    #  Note that only parameters that were actually accessed during interpretation will be reported.
    #
    class MissingParametersError < StandardError
      attr_reader :missing_params

      def initialize ( message, missing_params )
        super(message)
        @missing_params = missing_params
      end
    end

    def interpret ( elements )
      @missing_ids = []
      interpreted_value = interpret_subs(elements)
      if @raise_on_missing_params && !@missing_ids.empty?
        raise MissingParametersError.new('Missing parameters detected during interpretation', @missing_ids.compact)
      end

      interpreted_value
    end

    def interpret_subs ( elements, parent=nil )
      elements = elements.map do |element|
        interpret_element(element, parent)
      end

      # optimize common case
      if elements.length == 1
        return elements[0]
      end

      lambda do |args|
        elements.map { |element| element.call(args) }.join ''
      end
    end

    def interpret_element ( element, parent=nil )
      if element.is_a?(String)
        return lambda { |_=nil| element }
      end

      id, type, style = element
      offset = 0

      if id == '#'
        id = parent[0]
        type = 'number'
        offset = parent[2] || 0
        style = nil
      end

      id = id.to_sym # actual arguments should always be keyed by symbols

      case type
        when 'tag'
          interpret_tag(id, type, style[0], style[1], parent)
        when 'self-closing-tag'
          interpret_self_closing_tag(id, style[0])
        when 'number'
          interpret_number(id, offset, style)
        when 'date', 'time'
          interpret_date_time(id, type, style)
        when 'plural', 'selectordinal'
          offset = element[2]
          options = element[3]
          interpret_plural(id, type, offset, options)
        when 'select'
          interpret_select(id, style)
        when 'spellout', 'ordinal', 'duration'
          interpret_number(id, offset, type)
        else
          interpret_simple(id)
      end
    end

    def interpret_tag ( id, type, attributes, elements, parent )
      elements = elements.map do |element|
        interpret_element(element, parent)
      end

      lambda do |args|
        args ||= {}

        unless args[id]
          args[id] = lambda do |content|
            result = "<#{id}"
            result += " #{attributes}" unless attributes.empty?
            result += ">#{content}</#{id}>"
            result
          end
        end

        if elements.length == 1
          return args[id].call(elements[0].call(args))
        end

        args[id].call(
          (lambda do |nested|
            elements.map { |element| element.call(nested) }.join ''
          end).call(args)
        )
      end
    end

    def interpret_self_closing_tag (id, attributes)
      lambda do |args|
        args ||= {}

        unless args[id]
          args[id] = lambda do
            result = "<#{id}"
            result += " #{attributes}" unless attributes.empty?
            result += ' />'
            result
          end
        end

        args[id].call
      end
    end

    def interpret_number ( id, offset, style )
      locale = @locale
      lambda do |args|
        @missing_ids.push(id) unless args.key?(id)
        number = TwitterCldr::Localized::LocalizedNumber.new(args[id] - offset, locale)
        if style == 'integer'
          number.to_decimal.to_s(:precision => 0)
        elsif style == 'percent'
          number.to_percent.to_s
        elsif style == 'currency'
          number.to_currency.to_s
        elsif style == 'spellout'
          number.spellout
        elsif style == 'ordinal'
          number.to_rbnf_s('OrdinalRules', 'digits-ordinal')
        else
          number.to_s
        end
      end
    end

    def interpret_date_time ( id, type, style='medium' )
      locale = @locale
      lambda do |args|
        @missing_ids.push(id) unless args.key?(id)
        datetime = TwitterCldr::Localized::LocalizedDateTime.new(args[id], locale)
        datetime = type == 'date' ? datetime.to_date : datetime.to_time
        if style == 'medium'
          datetime.to_medium_s
        elsif style == 'long'
          datetime.to_long_s
        elsif style == 'short'
          datetime.to_short_s
        elsif style == 'full'
          datetime.to_full_s
        else
          datetime.to_additional_s(style)
        end
      end
    end

    def interpret_plural ( id, type, offset, children )
      parent = [ id, type, offset ]
      options = {}
      children.each do |key, value|
        options[key.to_sym] = interpret_subs(value, parent)
      end

      locale = @locale
      plural_type = type == 'selectordinal' ? :ordinal : :cardinal
      lambda do |args|
        @missing_ids.push(id) unless args.key?(id)
        arg = args[id]
        exactSelector = ('=' + arg.to_s).to_sym
        keywordSelector = TwitterCldr::Formatters::Plurals::Rules.rule_for(arg - offset, locale, plural_type)
        func =
          options[exactSelector] ||
          options[keywordSelector] ||
          options[:other]
        func.call(args)
      end
    end

    def interpret_select ( id, children )
      options = {}
      children.each do |key, value|
        options[key.to_sym] = interpret_subs(value, nil)
      end
      lambda do |args|
        @missing_ids.push(id) unless args.key?(id)
        selector = args[id].to_sym
        func =
          options[selector] ||
          options[:other]
        func.call(args)
      end
    end

    def interpret_simple ( id )
      lambda do |args|
        @missing_ids.push(id) unless args.key?(id)
        CGI.escapeHTML(args[id].to_s)
      end
    end

    def self.interpret ( elements, options=nil )
      Interpreter.new(options).interpret(elements)
    end

  end
end
