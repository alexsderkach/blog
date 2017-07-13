require "digest/sha1"

module Jekyll
  class Jupyter < Liquid::Block

    def initialize(tag_name, markup, tokens)
      super
    end

    def render(context)
      code_hash = Digest::SHA1.hexdigest(super)
      blog_dir = context["site"]["source"]
      jupyter_dir = File.join(context["site"]["source"], "_jupyter")
      html_path = File.join(jupyter_dir, "#{code_hash}.html")
      
      Dir.mkdir(jupyter_dir) unless Dir.exist?(jupyter_dir)
      if !File.file?(html_path)
        command = """
from nbformat import v3, v4;
code = \"\"\"#{super}\"\"\";
with open('#{html_path}', 'w') as f:
  f.write(v4.writes(v4.upgrade(v3.reads_py(code))));
        """
        system("python", "-c", command)
        system("jupyter","nbconvert",
                "--to", "html",
                "--template", "basic",
                "--execute",
                html_path,
                "--output", html_path)
      end
      html = File.read(html_path)
      <<-HTML
<div class="jupyter-notebook">#{html}</div>
      HTML
    end
  end
end

Liquid::Template.register_tag('jupyter', Jekyll::Jupyter)