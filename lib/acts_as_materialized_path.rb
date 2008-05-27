# ActsAsMaterializedPath
module ActiveRecord #:nodoc:
  module Acts #:nodoc:
    module MaterializedPath #:nodoc:
      #TODO - What's are appropraite exception types to raise?
      #Also, add more information to errors raised.
      class InvalidDelimiter < RangeError
      end
      class InvalidBase < RangeError
      end
      class InvalidAssignment < ArgumentError
      end
      class PathMaxExceeded < StandardError
      end
      class PathUpdateDisallowed < StandardError
      end
      class DestroyNotLeaf < TypeError
      end

      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods

        def acts_as_materialized_path(options = {})
          conf = {
            :delimiter => '.',
            :base => 36,
            :column => 'materialized_path',
            :places => 3,
          }
          conf.update(options) if options.is_a?(Hash)

          unless conf[:delimiter].length == 1 &&
              (' '..'/') === conf[:delimiter]
            raise InvalidDelimiter
          end

          unless (2..36) === conf[:base]
            raise InvalidBase
          end

          conf[:adapter] =
            ActiveRecord::Base.connection.adapter_name

          #configuration settings
          write_inheritable_attribute :mp_delimiter, conf[:delimiter]
          class_inheritable_reader :mp_delimiter

          write_inheritable_attribute :mp_base, conf[:base]
          class_inheritable_reader :mp_base

          write_inheritable_attribute :mp_column, conf[:column]
          class_inheritable_reader :mp_column

          write_inheritable_attribute :mp_places, conf[:places]
          class_inheritable_reader :mp_places

          #sql helpers
          write_inheritable_attribute :mp_like, "#{mp_column} like ?"
          class_inheritable_reader :mp_like

          write_inheritable_attribute :mp_eq, "#{mp_column} = ?"
          class_inheritable_reader :mp_eq

          write_inheritable_attribute :mp_gt, "#{mp_column} > ?"
          class_inheritable_reader :mp_gt

          write_inheritable_attribute :mp_gte, "#{mp_column} >= ?"
          class_inheritable_reader :mp_gte

          write_inheritable_attribute :mp_lt, "#{mp_column} < ?"
          class_inheritable_reader :mp_lt

          write_inheritable_attribute :mp_asc, "#{mp_column} ASC"
          class_inheritable_reader :mp_asc

          write_inheritable_attribute :mp_desc, "#{mp_column} DESC"
          class_inheritable_reader :mp_desc

          limit_string = '~' # This only works with and asci collating sequence
          limit_string = 'Z'*(mp_places+1) # This works with UTF-8

          write_inheritable_attribute :mp_ancestor_limit,
          case conf[:adapter]
          when 'MySQL'
            "concat(#{mp_column}, '#{limit_string}')"
          when 'SQLServer'
            "#{mp_column} + '#{limit_string}'"
          else # ANSI SQL Syntax
            "#{mp_column} || '#{limit_string}'"
          end
          class_inheritable_reader :mp_ancestor_limit

          write_inheritable_attribute :mp_between,
          "? between #{mp_column} and #{mp_ancestor_limit}"
          class_inheritable_reader :mp_between

          #path manipulation fu
          write_inheritable_attribute :mp_regexp,
          Regexp.new("[[:alnum:]]{#{conf[:places]}}\\#{conf[:delimiter]}$")
          class_inheritable_reader :mp_regexp


          include ActiveRecord::Acts::MaterializedPath::InstanceMethods
          extend ActiveRecord::Acts::MaterializedPath::SingletonMethods

          #before_create :before_create_callback

          attr_protected conf[:column].to_sym


          #if parent set, save as child
          #if sibling set, save as sibling
          #else save as root
          attr_accessor :mp_parent_id_for_save
          attr_accessor :mp_sibling_id_for_save

          #this mucks up emacs indenting, so watch out for that
          class_eval <<-EOV
            def #{mp_column}=(newpath)
              raise InvalidAssignment
            end
          EOV

        end
      end

      module SingletonMethods
        #
        def roots
          siblings('')
        end

        #
        def num2path_string(num)
          str = num.to_s(mp_base)
          len = str.length

          raise PathMaxExceeded unless len <= mp_places

          '0'*(mp_places-len)+str
        end

        #utility funtion to return a set of siblings
        def siblings(path, select = '*')
          find( :all,
                :select => select,
                :conditions =>
                [ mp_like, path + '_' * mp_places + mp_delimiter],
                :order => mp_asc )
        end


        def inner_delete(id)
          c = find(id, :select => mp_column)
        rescue RecordNotFound then
          return 0
        else
          count = 0
          c.children.each do |child|
            count += self.delete(child.id)
          end
          return count
        end

        #FIXME - handle arrays of ids
        def delete(id)
          transaction do
            inner_delete(id) + super(id)
          end
        end
      end

      module InstanceMethods
        #
        def left_most_child
          self.class.find(:first,
                          :conditions =>
                          ["#{mp_like}",
                           the_path + '_' * mp_places + mp_delimiter],
                          :order => mp_asc)
        end

        def is_leaf?
          !left_most_child
        end

        #
        def right_sibling
          self.class.find(:first,
                          :conditions =>
                          ["#{mp_gt} and #{mp_lt} and length(#{mp_column}) = ?",
                           the_path,
                           the_path(true)+'~',
                           the_path.length],
                          :order => mp_asc)
        end
        #
        def destroy
          raise DestroyNotLeaf unless children.length == 0
          #or
#           self.class.transaction do
#             children.each do |child|
#               child.destroy
#             end
#           end
          super
        end

        #
        def set_path(path)
          write_attribute(mp_column.to_sym, path)
        end

        #
        def nextvalue(path)
          last = self.class.find(:first,
                                 :select => mp_column,
                                 :conditions =>
                                 [mp_like, path +
                                  '_' * mp_places +
                                  mp_delimiter],
                                 :order => mp_desc,
                                 :lock => true)

          if last
            last_path = last.the_path
            if i = last_path.index(mp_regexp)
              leaf = last_path[i, mp_places]
            else
              leaf = last_path
            end
            nextval = leaf.to_i(mp_base).next
          else
            nextval = 0
          end

          return nextval
        end

        #
        def save
          if new_record? && !the_path
            self.class.transaction do
              basepath = ''
              if mp_parent_id_for_save.to_i > 0
                relation = mp_parent_id_for_save
                sibling = false
              elsif mp_sibling_id_for_save.to_i > 0
                relation = mp_sibling_id_for_save
                sibling = true
              end
              basepath =
                self.class.find(relation).the_path(sibling) if relation

              nextval = nextvalue(basepath)
              set_path(basepath+self.class.num2path_string(nextval)+mp_delimiter)
              super
            end
          else
            super
          end
        end

        #

        #
        def save_as_relation(parent_or_sibling, sibling)
          raise PathUpdateDisallowed unless new_record? && !the_path
          self.class.transaction do
            basepath = parent_or_sibling.the_path(sibling)
            nextval = nextvalue(basepath)
            set_path(basepath+self.class.num2path_string(nextval)+mp_delimiter)
            save
          end
        end

        #
        def save_as_sibling_of(sibling)
          save_as_relation(sibling, true)
        end

        #
        def save_as_child_of(parent)
          save_as_relation(parent, false)
        end

        #
        def the_path(truncate = false)
          materialized_path = self.send(mp_column)
          if truncate
            rex = Regexp.new('[[:alnum:]]{' + mp_places.to_s + '}' +
                             '\\' + mp_delimiter)
            offset = materialized_path.rindex(rex)
          end
          materialized_path = materialized_path[0, offset] if offset
          return materialized_path
        end

        #
        def siblings(include_self = false)
          res = self.class.siblings(the_path(true))
          res.delete_if{|mp| mp.the_path == the_path} unless include_self
          return res
        end

        # returns an array of children (empty if this is a leaf)
        def children
          self.class.siblings(the_path)
        end

        #
        def parent
          self.class.find(:first,
                          :conditions =>
                          [ mp_eq,
                            the_path(true) ])
        end

        # returns an array of parents to root
        def ancestors(include_self = false)
          self.class.find(:all,
                          :conditions =>
                          [ mp_between,
                            the_path(!include_self) ],
                          :order => mp_asc )
        end

        #returns the depth of this node in the tree (0 based)
        def depth
          the_path.count(mp_delimiter)-1
        end

        #TODO
        def descendants(include_self = false)
          self.class.find(:all,
                          :conditions =>
                          [ mp_like,
                            "#{the_path}%" ],
                          :order => mp_asc )
        end

      end
    end
  end
end

ActiveRecord::Base.send(:include, ActiveRecord::Acts::MaterializedPath)
