require 'spec_helper'

describe MessageFormat do
  describe '.new' do
    it 'throws an error on bad syntax' do
      expect { MessageFormat.new({}) }.to raise_error
      expect { MessageFormat.new('no finish arg {') }.to raise_error
      expect { MessageFormat.new('no start arg }') }.to raise_error
      expect { MessageFormat.new('empty arg {}') }.to raise_error
      expect { MessageFormat.new('unfinished select { a, select }') }.to raise_error
      expect { MessageFormat.new('unfinished select { a, select, }') }.to raise_error
      expect { MessageFormat.new('sub with no selector { a, select, {hi} }') }.to raise_error
      expect { MessageFormat.new('sub with no other { a, select, foo {hi} }') }.to raise_error
      expect { MessageFormat.new('wrong escape \\{') }.to raise_error
      expect { MessageFormat.new("wrong escape \'{\'', 'en', { escape: '\\' }") }.to raise_error
      expect { MessageFormat.new('bad arg type { a, bogus, nope }') }.to raise_error
      expect { MessageFormat.new('bad arg separator { a bogus, nope }') }.to raise_error
      expect { MessageFormat.new('unclosed tag <a>Tag') }.to raise_error
      expect { MessageFormat.new('un matching tag </a>Tag') }.to raise_error
      expect { MessageFormat.new('nested un matching tag <a>Tag</B></a>') }.to raise_error
      expect { MessageFormat.new('mis matched tags <a>Tag</b>') }.to raise_error
    end
  end

  describe '#format' do
    it 'formats a simple message' do
      pattern = 'Simple string with nothing special'
      message = MessageFormat.new(pattern, 'en-US').format()

      expect(message).to eql('Simple string with nothing special')
    end

    it 'formats tags' do
      pattern = 'Simple string with <A>tags</A>'
      message = MessageFormat.new(pattern, 'en-US').format({ A: lambda { |content| "<a href=\"https://google.com\">#{content}</a>" } })

      expect(message).to eql('Simple string with <a href="https://google.com">tags</a>')
    end

    it 'defaults when no arg provided' do
      pattern = 'Simple string with <A>tags</A>'
      message = MessageFormat.new(pattern, 'en-US').format()

      expect(message).to eql('Simple string with <A>tags</A>')
    end

    it 'defaults when no arg provided for self closing' do
      pattern = 'Simple string with <A />tags'
      message = MessageFormat.new(pattern, 'en-US').format()

      expect(message).to eql('Simple string with <A />tags')
    end

    it 'formats nested tags' do 
      pattern = 'Simple string with <A>tags<B>This is nested</B></A>'
      message = MessageFormat.new(pattern, 'en-US').format(
        { 
          A: lambda { |content| "<a href=\"https://google.com\">#{content}</a>" },
          B: lambda { |content| "<b>#{content}</b>" }
        }
      )

      expect(message).to eql('Simple string with <a href="https://google.com">tags<b>This is nested</b></a>')
    end

    it 'prevents xss' do
      pattern = 'My Template <a>{user_content}</a>'
      message = MessageFormat.new(pattern, 'en-US').format(
        {
          a: lambda { |content| content },
          user_content: "<script>alert('i am evil');</script>"
        }
      )

      expect(message).to eql('My Template &lt;script&gt;alert(&#39;i am evil&#39;);&lt;/script&gt;')
    end

    it 'formats tags in switch case' do
      pattern = '{gender, select, male {&lt; hello <b>world</b> {token} &lt;&gt; <a>{placeholder}</a>} female {<b>foo &lt;&gt; bar</b>} other {<b>foo &lt;&gt; bar</b>}}'
      message = MessageFormat.new(pattern, 'en-US').format(
        { 
          gender: 'male',
          b: lambda { |str| str },
          token: '<asd>',
          placeholder: '>',
          a: lambda { |str| str },
        }
      )

      expect(message).to eql('&lt; hello world &lt;asd&gt; &lt;&gt; &gt;')

      message = MessageFormat.new(pattern, 'en-US').format(
        { 
          gender: 'female',
          b: lambda { |str| str }
        }
      )

      expect(message).to eql('foo &lt;&gt; bar')
    end

    it 'deep format nested tag message' do
      pattern = 'hello <b>world<i>!</i> <br/> </b>'

      message = MessageFormat.new(pattern, 'en-US').format(
        { 
          b: lambda { |content| ['<b>', *content, '</b>'] },
          i: lambda { |content| "$$$#{content}$$$" }
        }
      )

      expect(message).to eql('hello <b>world$$$!$$$ <br /> </b>')
    end

    it 'formats tags in plurals' do
      pattern = 'You have {count, plural, =1 {<b>1</b> Message} other {<b>#</b> Messages}}'
      message = MessageFormat.new(pattern, 'en-US').format(
        {
          b: lambda { |chunks| "{}#{chunks}{}" },
          count: 1000
        }
      )

      expect(message).to eql('You have {}1,000{} Messages')
    end

    it 'formats self closing tags' do 
      pattern = 'Simple string with <A />'
      message = MessageFormat.new(pattern, 'en-US').format(
        {
          A: lambda { '<hr />' }
        }
      )

      expect(message).to eql('Simple string with <hr />')
    end

    it 'formats correctly with hash' do 
      pattern = 'Simple string with <A>#</A>'
      message = MessageFormat.new(pattern, 'en-US').format(
        {
          A: lambda { |content| "<a>#{content}</a>" }
        }
      )

      expect(message).to eql('Simple string with <a>#</a>')
    end

    it 'handles pattern with escaped text' do
      pattern = 'This isn\'\'t a \'{\'\'simple\'\'}\' \'string\''
      message = MessageFormat.new(pattern, 'en-US').format()

      expect(message).to eql('This isn\'t a {\'simple\'} \'string\'')
    end

    it 'accepts arguments' do
      pattern = 'x{ arg }z'
      message = MessageFormat.new(pattern, 'en-US').format({ :arg => 'y' })

      expect(message).to eql('xyz')
    end

    it 'formats numbers, dates, and times' do
      pattern = '{ n, number } : { d, date, short } { d, time, short }'
      message = MessageFormat.new(pattern, 'en-US').format({ :n => 0, :d => DateTime.new })

      expect(message).to match(/^0 \: \d\d?\/\d\d?\/\d{2,4} \d\d?\:\d\d [AP]M$/)
    end

    it 'formats integer number' do
      pattern = '{ n, number, integer }'
      message = MessageFormat.new(pattern, 'en-US').format({ n: 1234 })

      expect(message).to match('1,234')
    end

    it 'handles plurals' do
      pattern =
        'On {takenDate, date, short} {name} {numPeople, plural, offset:1
            =0 {didn\'t carpool.}
            =1 {drove himself.}
         other {drove # people.}}'
      message = MessageFormat.new(pattern, 'en-US')
          .format({ :takenDate => DateTime.now, :name => 'Bob', :numPeople => 5 })

      expect(message).to match(/^On \d\d?\/\d\d?\/\d{2,4} Bob drove 4 people.$/)
    end

    it 'handles plurals for other locales' do
      pattern =
        '{n, plural,
          zero {zero}
           one {one}
           two {two}
           few {few}
          many {many}
         other {other}}'
      message = MessageFormat.new(pattern, 'ar')

      expect(message.format({ n: 0 })).to eql('zero')
      expect(message.format({ n: 1 })).to eql('one')
      expect(message.format({ n: 2 })).to eql('two')
      expect(message.format({ n: 3 })).to eql('few')
      expect(message.format({ n: 11 })).to eql('many')
    end

    it 'handles selectordinals' do
      pattern =
        '{n, selectordinal,
           one {#st}
           two {#nd}
           few {#rd}
         other {#th}}'
      message = MessageFormat.new(pattern, 'en')

      expect(message.format({ n: 1 })).to eql('1st')
      expect(message.format({ n: 22 })).to eql('22nd')
      expect(message.format({ n: 103 })).to eql('103rd')
      expect(message.format({ n: 4 })).to eql('4th')
    end

    it 'handles select' do
      pattern =
        '{ gender, select,
           male {it\'s his turn}
         female {it\'s her turn}
          other {it\'s their turn}}'
      message = MessageFormat.new(pattern, 'en-US')
          .format({ gender: 'female' })

      expect(message).to eql('it\'s her turn')
    end

    it 'should throw an error when args are expected and not passed' do
      expect { MessageFormat.new('{a}').format() }.to raise_error
    end
  end

  describe '.formatMessage' do
    it 'formats messages' do
      pattern =
        'On {takenDate, date, short} {name} {numPeople, plural, offset:1
            =0 {didn\'t carpool.}
            =1 {drove himself.}
         other {drove # people.}}'
      message = MessageFormat.format_message(pattern,
        :takenDate => DateTime.now,
        :name => 'Bob',
        :numPeople => 5
      )
      expect(message).to match(/^On \d\d?\/\d\d?\/\d{2,4} Bob drove 4 people.$/)

      message = MessageFormat::format_message(pattern,
        :takenDate => DateTime.now,
        :name => 'Bill',
        :numPeople => 6
      )
      expect(message).to match(/^On \d\d?\/\d\d?\/\d{2,4} Bill drove 5 people.$/)
    end
  end

  describe 'locales' do
    it 'doesn\'t throw for any locale\'s plural function' do
      pattern =
        '{n, plural,
          zero {zero}
           one {one}
           two {two}
           few {few}
          many {many}
         other {other}}'
      TwitterCldr.supported_locales.each do |locale|
        message = MessageFormat.new(pattern, locale)
        for n in 0..200 do
          result = message.format({ :n => n })
          expect(result).to match(/^(zero|one|two|few|many|other)$/)
        end
      end
    end
  end
end
