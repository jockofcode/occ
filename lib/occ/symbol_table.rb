# frozen_string_literal: true

module OCC
  # Scoped symbol table. Each scope is a Hash; scopes stack.
  class SymbolTable
    Symbol = Struct.new(:name, :type, :kind, :location) # kind: :var, :func, :typedef, :enum_const

    def initialize
      @scopes = [{}]   # global scope
    end

    def push_scope
      @scopes.push({})
    end

    def pop_scope
      @scopes.pop
    end

    def define(name, type:, kind:, location: nil)
      @scopes.last[name] = Symbol.new(name, type, kind, location)
    end

    def lookup(name)
      @scopes.reverse_each { |scope| return scope[name] if scope.key?(name) }
      nil
    end

    def defined_in_current_scope?(name)
      @scopes.last.key?(name)
    end

    def global_scope
      @scopes.first
    end
  end
end
