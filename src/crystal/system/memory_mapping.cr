{% if flag?(:win32) %}
  require "./win32/memory_mapping"
{% else %}
  require "./unix/memory_mapping"
{% end %}
