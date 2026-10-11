# extension to string
class String
  def camelize(separator: '_')
    gsub(/#{separator}([a-z0-9])/) { Regexp.last_match(1).upcase }
  end
end
