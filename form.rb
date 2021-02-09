# Copyright 2019 Victor David Santos
#
# This file is part of Super Bombinhas.
#
# Super Bombinhas is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Super Bombinhas is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Super Bombinhas.  If not, see <https://www.gnu.org/licenses/>.

require_relative 'global'
include MiniGL

module FormElement
  attr_reader :x, :y, :start_x, :start_y, :initialized

  def init_movement
    @start_x = @x
    @start_y = @y
    @initialized = true
  end

  def move_to(x, y)
    @aim_x = x
    @aim_y = y
  end

  def update_movement
    if @aim_x
      dist_x = @aim_x - @x
      dist_y = @aim_y - @y
      if dist_x.round == 0 and dist_y.round == 0
        @x = @aim_x
        @y = @aim_y
        @aim_x = @aim_y = nil
      else
        set_position(@x + dist_x / 5.0, @y + dist_y / 5.0)
      end
    end
  end
end

class MenuElement
  include FormElement

  def update; end

  def set_position(x, y)
    @x = x; @y = y
  end
end

class MenuText < MenuElement
  attr_reader :text_id
  attr_writer :text

  def initialize(text_or_id, x, y, width = 760, mode = :justified, scale = 2)
    if text_or_id.is_a?(String)
      @text = text_or_id
      @text_id = nil
    else
      @text_id = text_or_id
      @text = SB.text(text_or_id)
    end
    @x = x
    @y = y
    @width = width
    @mode = mode
    @scale = scale
  end

  def draw
    SB.text_helper.write_breaking(@text, @x, @y, @width, @mode, 0, 255, 0, @scale, @scale)
  end
end

class MenuNumber < MenuElement
  attr_accessor :num

  def initialize(num, x, y, mode, color = 0)
    @num = num
    @x = x
    @y = y
    @mode = mode
    @color = color
  end

  def draw
    SB.text_helper.write_line(@num.to_s, @x, @y, @mode, @color)
  end
end

class MenuButton < Button
  include FormElement

  attr_reader :back, :text_id

  def initialize(y, text_id, back = false, x = 314, &action)
    super(x, y, SB.font, SB.text(text_id), :ui_button1, 0, 0x808080, 0, 0, true, true, 0, 7, 0, 0, 0, nil, 2, 2, &action)
    @text_id = text_id
    @back = back
    @sound = Res.sound(back ? :btn2 : :btn1)
  end

  def click
    @action.call @params
    SB.play_sound @sound
  end
end

class MenuArrowButton < Button
  include FormElement

  def initialize(x, y, type, &action)
    super(x, y, nil, nil, "ui_button#{type}", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, nil, 2, 2, &action)
    @sound = Res.sound :btn3
  end

  def click
    @action.call @params
    SB.play_sound @sound
  end
end

class MenuTextField < TextField
  include FormElement

  def initialize(y, x = 314)
    super x: x, y: y, font: SB.font, img: :ui_textField, margin_x: 5, margin_y: 3, locale: (SB.lang == :portuguese ? 'pt-br' : 'en-us'), scale_x: 2, scale_y: 2
  end
end

class FormSection
  attr_reader :cur_btn, :changing

  def initialize(components, visible = false)
    @components = components
    @buttons = []
    @components.each do |c|
      if c.is_a? Button or c.is_a? TextField
        @buttons << c
        @back_btn = c if c.respond_to?(:back) && c.back
      end
      unless c.initialized
        c.init_movement
        c.set_position(c.x - C::SCREEN_WIDTH, c.y) unless visible
      end
    end
    @visible = visible
    @changing = nil
    @cur_btn = @buttons[@cur_btn_index = 0]
    @cur_btn.focus if @cur_btn.respond_to? :focus
  end

  def update(mouse_moved)
    if @changing
      @components.each do |c|
        if c.update_movement.nil?
          @visible = false if @changing == 0
          @changing = nil
        end
      end
    elsif @visible
      @components.each { |c| c.update }
      @buttons.each_with_index do |b, i|
        next unless b.is_a? Button
        if b.state == :down || mouse_moved && b.state == :over
          @cur_btn_index = i
          break
        end
      end
      if SB.key_pressed?(:down) || SB.key_pressed?(:right) && @cur_btn.is_a?(Button)
        @cur_btn_index += 1
        @cur_btn_index = 0 if @cur_btn_index == @buttons.length
        @cur_btn.unfocus if @cur_btn.respond_to? :unfocus
      elsif SB.key_pressed?(:up) || SB.key_pressed?(:left) && @cur_btn.is_a?(Button)
        @cur_btn_index -= 1
        @cur_btn_index = @buttons.length - 1 if @cur_btn_index < 0
        @cur_btn.unfocus if @cur_btn.respond_to? :unfocus
      elsif SB.key_pressed?(:confirm)
        @cur_btn.click if @cur_btn.respond_to? :click
      elsif @back_btn && (SB.key_pressed?(:back) && !@cur_btn.is_a?(TextField) ||
                          KB.key_pressed?(Gosu::KB_ESCAPE) || KB.key_pressed?(Gosu::GP_0_BUTTON_1))
        @back_btn.click
      end
      @cur_btn = @buttons[@cur_btn_index]
      @cur_btn.focus if @cur_btn.respond_to? :focus
    end
  end

  def show
    @visible = true
    @changing = 1
    @components.each { |c| c.move_to(c.start_x, c.y) }
  end

  def hide
    @changing = 0
    @components.each { |c| c.move_to(c.x - C::SCREEN_WIDTH, c.y) }
  end

  def clear
    @components.clear
    @buttons.clear
    @cur_btn = nil
  end

  def reset
    @cur_btn = @buttons[@cur_btn_index = 0]
    @buttons.select { |b| b.is_a?(TextField) }.each { |t| t.text = '' }
  end

  def update_lang
    @components.each do |c|
      c.text = SB.text(c.text_id).gsub("\\n", "\n") if c.respond_to?(:text_id) && c.text_id
      c.locale = (SB.lang == :portuguese ? 'pt-br' : 'en-us') if c.respond_to? :locale=
    end
  end

  def add(component)
    @components << component
    if component.is_a? Button
      @buttons << component
      @cur_btn = @buttons[@cur_btn_index = 0] if @cur_btn.nil?
      @back_btn = component if component.respond_to?(:back) && component.back
    end
    component.init_movement
    component.set_position(component.x - C::SCREEN_WIDTH, component.y) unless @visible
  end

  def draw
    @components.each { |c| c.draw } if @visible
  end
end

class Form
  attr_reader :cur_section_index

  def initialize(*section_components)
    @sections = [FormSection.new(section_components.shift, true)]
    section_components.each do |c|
      @sections << FormSection.new(c)
    end
    @highlight = Res.imgs(:ui_highlight, 3, 3, true)
    @highlight_alpha = 102
    @highlight_state = 0
    @cur_section = @sections[@cur_section_index = 0]
    # @cur_section.show
  end

  def update
    mouse_moved = Mouse.x != @mouse_prev_x || Mouse.y != @mouse_prev_y
    @mouse_prev_x = Mouse.x
    @mouse_prev_y = Mouse.y

    @sections.each { |s| s.update(mouse_moved) }
    update_highlight unless @cur_section.changing
  end

  def update_highlight
    if @highlight_state == 0
      @highlight_alpha += 3
      @highlight_state = 1 if @highlight_alpha == 255
    else
      @highlight_alpha -= 3
      @highlight_state = 0 if @highlight_alpha == 102
    end
  end

  def go_to_section(index)
    @cur_section.hide
    @cur_section = @sections[@cur_section_index = index]
    @cur_section.reset
    @cur_section.show
  end

  def section(index)
    @sections[index]
  end

  def reset
    @sections.each { |s| s.reset }
    go_to_section 0
  end

  def update_lang
    @sections.each { |s| s.update_lang }
  end

  def draw
    @sections.each { |s| s.draw }
    draw_highlight unless @cur_section.changing
  end

  def draw_highlight
    btn = @cur_section.cur_btn
    x = btn.x; y = btn.y; w = btn.w; h = btn.h
    color1 = (@highlight_alpha << 24) | 0xffffff
    color2 = (((@highlight_alpha * 0.5).round) << 24) | 0xffffff
    draw_sliced(@highlight, x - 2, y - 2, w, h, color1)
    draw_sliced(@highlight, x - 4, y - 4, w + 4, h + 4, color2)
  end

  def draw_sliced(img, x, y, w, h, color)
    h_b = 2 * img[0].width
    h_scale = w.to_f / img[0].width
    v_b = 2 * img[0].height
    v_scale = h.to_f / img[0].height
    img[0].draw(x, y, 0, 2, 2, color)
    img[1].draw(x + h_b, y, 0, h_scale, 2, color)
    img[2].draw(x + h_b + w, y, 0, 2, 2, color)
    img[3].draw(x, y + v_b, 0, 2, v_scale, color)
    # img[4].draw(x + h_b, y + v_b, 0, h_scale, v_scale, color)
    img[5].draw(x + h_b + w, y + v_b, 0, 2, v_scale, color)
    img[6].draw(x, y + v_b + h, 0, 2, 2, color)
    img[7].draw(x + h_b, y + v_b + h, 0, h_scale, 2, color)
    img[8].draw(x + h_b + w, y + v_b + h, 0, 2, 2, color)
  end
end
