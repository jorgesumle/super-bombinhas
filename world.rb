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

require 'minigl'
require_relative 'stage'
include MiniGL

class MapStage
  attr_reader :x, :y, :img

  def initialize(world, num, x, y, img)
    @x = x
    @y = y
    @img = Res.img "icon_#{img}"
    @glows = img != :unknown
    @state = 0
    @alpha =
      if @glows
        0xff
      else
        0x7f
      end

    @world = world
    @num = num

    update_icons
  end

  def name
    SB.text("stage_#{@world}_#{@num}")
  end

  def update
    update_icons
    return unless @glows
    if @state == 0
      @alpha -= 2
      if @alpha == 0x7f
        @state = 1
      end
    else
      @alpha += 2
      if @alpha == 0xff
        @state = 0
      end
    end
  end

  def update_icons
    @has_all_stars = SB.player.all_stars.index("#{@world}-#{@num}")
    @has_spec = SB.player.specs.index("#{@world}-#{@num}")
  end

  def select(loaded_stage)
    SB.stage = Stage.new(@world, @num)
    SB.stage.start(@num == loaded_stage)
    SB.state = :main
  end

  def open
    @img = Res.img :icon_current
    @glows = true
    @alpha = 0xff
  end

  def close
    @img = Res.img :icon_complete
  end

  def draw(alpha)
    a = ((alpha / 255.0) * (@alpha / 255.0) * 255).round
    @img.draw @x, @y, 0, 2, 2, (a << 24) | 0xffffff
    Res.img(:icon_star).draw(@x - 9, @y - 9, 0, 2, 2) if @has_all_stars
    Res.img(:icon_spec).draw(@x + 23, @y - 9, 0, 1.5, 1.5) if @has_spec
  end
end

class World
  attr_reader :num, :stage_count, :song

  ITEM_ICONS = {
    Section::ELEMENT_TYPES.key(Attack1)   => :icon_Attack1,
    Section::ELEMENT_TYPES.key(BoardItem) => :icon_board,
    Section::ELEMENT_TYPES.key(Key)       => :icon_Key0,
    Section::ELEMENT_TYPES.key(Shield)    => :icon_shield,
    Section::ELEMENT_TYPES.key(Attack2)   => :icon_attack2,
    Section::ELEMENT_TYPES.key(Spring)    => :icon_spring,
    Section::ELEMENT_TYPES.key(Attack3)   => :icon_Attack3,
  }

  def initialize(num = 1, stage_num = 1, loaded = false)
    @num = num
    @loaded_stage = loaded ? stage_num : nil

    @water = Sprite.new 0, 0, :ui_water, 2, 2
    @mark = GameObject.new 0, 0, 1, 1, :ui_mark
    @arrow = Res.img :ui_changeWorld
    @parchment = Res.img :ui_parchment
    @secret_world = Res.img :ui_secretWorld if SB.player.last_world == C::LAST_WORLD
    @map = Res.img "bg_world#{num}"
    @startup_item_frame = Res.img(:ui_startupItem)
    @song = Res.song("w#{@num}")

    @stages = []
    lines = nil
    File.open("#{Res.prefix}stage/#{@num}/world") do |f|
      lines = f.read.split("\n")
    end
    @stage_count = lines.size - 1
    lines.each_with_index do |l, i|
      coords = l.split ','
      if i == 0
        @mark.x = coords[0].to_i
        @mark.y = coords[1].to_i
        next
      end
      state = SB.stage_completion(num, i, @stage_count)
      @stages << MapStage.new(@num, i, coords[0].to_i, coords[1].to_i, state)
    end
    @enabled_stage_count = num < SB.player.last_world ? @stage_count : SB.player.last_stage
    @cur = (loaded ? @loaded_stage : @enabled_stage_count) - 1
    @bomb = Sprite.new 0, 0, "sprite_Bomba#{SB.player.bomb.type.to_s.capitalize}", 6, 4
    set_bomb_position
    @trans_alpha = 0
    @secret_world_alpha = 255
  end

  def resume(show_secret_world_animation = false)
    SB.play_song @song
    SB.state = :map
    if show_secret_world_animation
      @opening_secret_world = true
      @secret_world_alpha = 0
      @timer = 0
      @secret_world_highlight = Res.img(:ui_secretWorldHighlight)
    end
  end

  def update
    @water.animate [0, 1, 2, 3], 6
    @bomb.animate [0, 1, 0, 2], 8

    if @next_world
      @trans_alpha -= 17
      @mark.move_free(@mark_aim, @mark_speed)
      if @trans_alpha == 0
        SB.world = World.new(@next_world)
        SB.play_song(SB.world.song)
      end
      return
    elsif @trans_alpha < 0xff
      @trans_alpha += 17
    end

    if @opening_secret_world
      @timer += 1 if @timer < 60
      if @timer == 60
        if @secret_world_alpha < 0
          @secret_world_alpha += 5
          if @secret_world_alpha == 0
            @opening_secret_world = false
            @secret_world_alpha = 255
          end
        else
          @secret_world_alpha += 5
          if @secret_world_alpha == 255
            @secret_world_alpha = -125
          end
        end
      end
    end

    @stages.each(&:update)

    if SB.key_pressed?(:back)
      Menu.reset
      SB.state = :menu
    elsif SB.key_pressed?(:confirm)
      @stages[@cur].select(@loaded_stage)
    elsif @cur > 0 && (SB.key_pressed?(:left) || SB.key_pressed?(:down))
      @cur -= 1
      set_bomb_position
    elsif @cur < @enabled_stage_count - 1 && (SB.key_pressed?(:right) || SB.key_pressed?(:up))
      @cur += 1
      set_bomb_position
    elsif SB.key_pressed?(:prev) and @num > 1
      change_world(@num - 1)
    elsif SB.key_pressed?(:next) and @num < SB.player.last_world
      change_world(@num + 1)
    end
  end

  def set_bomb_position
    @bomb.x = @stages[@cur].x - 4; @bomb.y = @stages[@cur].y - 15
  end

  def set_loaded(stage_num)
    @loaded_stage = stage_num
    @bomb = Sprite.new 0, 0, "sprite_Bomba#{SB.save_data[3].capitalize}", 5, 2
    set_bomb_position
  end

  def open_stage(continue)
    @stages[@cur].close
    if @cur < @stage_count - 1
      @stages[@cur + 1].open
      @enabled_stage_count += 1
      if continue
        @cur += 1
        set_bomb_position
      end
    end
  end

  def change_world(num)
    @next_world = num
    f = File.open("#{Res.prefix}stage/#{@next_world}/world")
    coords = f.readline.split ','
    @mark_aim = Vector.new(coords[0].to_i, coords[1].to_i)
    @mark_speed = @mark_aim.distance(@mark.position) / 15
    f.close
  end

  def draw
    G.window.clear 0x6ab8ff
    tint_color = (@trans_alpha << 24) | 0xffffff
    y = 0
    while y < C::SCREEN_HEIGHT
      x = 0
      while x < C::SCREEN_WIDTH
        @water.x = x; @water.y = y
        @water.draw(nil, 2, 2)
        x += 40
      end
      y += 40
    end
    @map.draw 0, 0, 0, 2, 2, tint_color
    @parchment.draw 0, 0, 0, 2, 2
    if @secret_world
      color = @secret_world_alpha >= 0 ? (@secret_world_alpha << 24) | 0xffffff : 0xffffffff
      @secret_world.draw 88, 112, 0, 2, 2, color
    end
    if @opening_secret_world
      color = (@secret_world_alpha < 0 ? -@secret_world_alpha : 130) << 24
      G.window.draw_quad(0, 0, color, C::SCREEN_WIDTH, 0, color, 0, 97, color, C::SCREEN_WIDTH, 97, color, 1)
      G.window.draw_quad(0, 97, color, 87, 97, color, 0, 197, color, 87, 197, color, 1)
      G.window.draw_quad(0, 197, color, C::SCREEN_WIDTH, 197, color, 0, C::SCREEN_HEIGHT, color, C::SCREEN_WIDTH, C::SCREEN_HEIGHT, color, 1)
      G.window.draw_quad(187, 97, color, C::SCREEN_WIDTH, 97, color, 187, 197, color, C::SCREEN_WIDTH, 197, color, 1)
      @secret_world_highlight.draw(87, 97, 1, 2, 2, color)
    end
    @mark.draw nil, 2, 2

    line_color = @trans_alpha << 24
    @stages.each_with_index do |s, i|
      s.draw @trans_alpha
      if i < @stages.size - 1
        sx = s.x + s.img.width
        sy = s.y + s.img.height
        dx = @stages[i + 1].x + @stages[i + 1].img.width - sx
        dy = @stages[i + 1].y + @stages[i + 1].img.height - sy
        d = Math.sqrt(dx * dx + dy * dy)
        p = s.img.width + 2
        while p <= d - s.img.width - 2
          x = sx + p / d * dx
          y = sy + p / d * dy
          G.window.draw_quad(x - 2, y - 2, tint_color, x + 2, y - 2, tint_color, x - 2, y + 2, tint_color, x + 2, y + 2, tint_color, 0)
          G.window.draw_quad(x - 1, y - 1, line_color, x + 1, y - 1, line_color, x - 1, y + 1, line_color, x + 1, y + 1, line_color, 0)
          p += 10
        end
      end
    end

    @bomb.draw nil, 2, 2, @trans_alpha
    if SB.player.startup_item
      @startup_item_frame.draw(265, 546, 0, 2, 2, tint_color)
      Res.img(ITEM_ICONS[SB.player.startup_item]).draw(273, 554, 0, 2, 2, tint_color)
    end

    SB.text_helper.write_line(text: SB.text("world_#{@num}"), x: 525, y: 10, mode: :center, alpha: @trans_alpha, scale_x: 3, scale_y: 3)
    SB.text_helper.write_breaking("#{@num}-#{@cur+1}: #{@stages[@cur].name}", 525, 55, 390, :center, 0, @trans_alpha)
    SB.text_helper.write_breaking(SB.text(:ch_st_instruct).gsub('\n', "\n"), 780, 545, 600, :right, 0, @trans_alpha)

    if @num > 1
      @arrow.draw 260, 10, 0, 2, 2, tint_color
      SB.text_helper.write_line 'Z', 297, 15, :center, 0, @trans_alpha
    end
    if @num < SB.player.last_world
      @arrow.draw 790, 10, 0, -2, 2, tint_color
      SB.text_helper.write_line 'V', 753, 15, :center, 0, @trans_alpha
    end
    if @cur > 0
      @arrow.draw 260, 47, 0, 2, 2, tint_color
      SB.text_helper.write_line '←', 297, 52, :center, 0, @trans_alpha
    end
    if @cur < @enabled_stage_count - 1
      @arrow.draw 790, 47, 0, -2, 2, tint_color
      SB.text_helper.write_line '→', 753, 52, :center, 0, @trans_alpha
    end
  end
end
