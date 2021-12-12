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

############################### classes abstratas ##############################

module Item
  attr_reader :icon

  def check(switch)
    if switch[:state] == :taken
      SB.player.add_item switch
      switch[:obj] = self
      return true
    elsif switch[:state] == :used
      return true
    end
    false
  end

  def set_icon(icon)
    @icon = Res.img "icon_#{icon}"
  end

  def take(section, store, x = nil, y = nil, sound_id = :getItem)
    info = SB.stage.find_switch self
    if store
      SB.player.add_item(info)
      StageMenu.play_get_item_effect(x, y) if x && y
      info[:state] = :temp_taken
    else
      use section, info
      info[:state] = :temp_taken_used
    end
    SB.play_sound(Res.sound(sound_id))
  end

  def set_switch(switch)
    switch[:state] = if switch[:state] == :taken
                       :taken_temp_used
                     elsif switch[:state] == :temp_taken
                       :temp_taken_used
                     else
                       :temp_used
                     end
  end
end

class FloatingItem < GameObject
  include Item

  attr_reader :bomb_type

  def initialize(x, y, w, h, img, img_gap = nil, sprite_cols = nil, sprite_rows = nil, indices = nil, interval = nil, bomb_type = nil)
    super x, y, w, h, img, img_gap, sprite_cols, sprite_rows
    img_gap = Vector.new(0, 0) if img_gap.nil?
    @active_bounds = Rectangle.new x + img_gap.x, y + img_gap.y, @img[0].width * 2, @img[0].height * 2
    @state = 3
    @counter = 0
    @indices = indices
    @interval = interval
    @bomb_type = bomb_type
  end

  def update(section)
    if SB.player.bomb.collide?(self) and (@bomb_type.nil? or SB.player.bomb.type == @bomb_type)
      yield
      @dead = true
      return
    end
    unless SB.stage.stopped == :all
      @counter += 1
      if @counter == 10
        if @state == 0 or @state == 1; @y -= 1
        else; @y += 1; end
        @state += 1
        @state = 0 if @state == 4
        @counter = 0
      end
      animate @indices, @interval if @indices
    end
  end

  def take_anim(section, store)
    take(section, store, @x - section.map.cam.x + @w, @y - section.map.cam.y)
  end

  def stop_time_immune?
    true
  end

  def draw(map, section = nil, scale_x = 2, scale_y = 2, alpha = 255, color = 0xffffff)
    super(map, scale_x, scale_y, alpha, color)
  end
end

################################################################################

class FireRock < FloatingItem
  LIGHT_TILES = [
    [0, 0, 0],
    [-1, 0, 50], [0, -1, 50], [1, 0, 50], [0, 1, 50],
    [-1, -1, 125], [1, -1, 125], [-1, 1, 125], [1, 1, 125]
  ]

  def initialize(x, y, args, section)
    super x + 6, y + 7, 20, 20, :sprite_FireRock, Vector.new(-2, -17), 4, 1, [0, 1, 2, 3], 5
    @score = case args
             when '1' then 10
             when '2' then 20
             when '3' then 50
             else          10
             end
    @color = case args
             when '1' then 0xff6600
             when '2' then 0x33ff33
             when '3' then 0x3399ff
             else          0xff9933
             end
    @active_bounds.x -= C::TILE_SIZE
    @active_bounds.y -= C::TILE_SIZE
    @active_bounds.w += 2 * C::TILE_SIZE
    @active_bounds.h += 2 * C::TILE_SIZE
  end

  def update(section)
    super(section) do
      SB.player.stage_score += @score
      SB.play_sound(Res.sound(:getFire))
    end
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, @color)
    section.add_light_tiles(LIGHT_TILES, @x, @y, @w, @h)
  end
end

class Life < FloatingItem
  def initialize(x, y, args, section, switch)
    return if check switch
    args = (args || '1').split(',', 3)

    if args[1] == '$'
      w = 32
      h = 32
      img = :sprite_megalife
    else
      x += 2
      y += 2
      w = 28
      h = 28
      img = :sprite_Life
    end
    super x, y, w, h, img, nil, 8, 1,
      [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7], 6
    @lives = args[1] == '$' ? 5 : 1
  end

  def update(section)
    super(section) do
      take(section, false)
      StageMenu.play_get_item_effect(@x - section.map.cam.x + @w / 2, @y - section.map.cam.y + @h / 2, :life)
      section.add_effect(ScoreEffect.new(@x + @w / 2, @y, @lives, true))
    end
  end

  def use(section, switch)
    SB.stage.life_count += @lives
    set_switch(switch)
    true
  end
end

class Key < FloatingItem
  def initialize(x, y, args, section, switch)
    @type = args.to_i
    set_icon "Key#{@type}"
    switch[:extra] = @type
    return if check switch
    super x + 3, y + 3, 26, 26, "sprite_Key#{@type}", Vector.new(-3, -3)
  end

  def update(section)
    super(section) do
      take_anim(section, true)
    end
  end

  def use(section, switch)
    obj = section.active_object
    if obj.is_a?(Door) && obj.locked && @type == obj.type
      obj.unlock(section)
      set_switch(switch)
    end
  end
end

class Attack1 < FloatingItem
  def initialize(x, y, args, section, switch)
    set_icon :Attack1
    if check switch
      @bomb_type = :azul
      return
    end
    super x + 2, y + 2, 28, 28, :sprite_Attack1, nil, 8, 1,
      [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7], 6, :azul
  end

  def update(section)
    super(section) do
      take_anim(section, true)
    end
  end

  def use(section, switch)
    b = SB.player.bomb
    return false if b.type != @bomb_type
    angle = if b.facing_right; 0
    else; 180;         end
    section.add Projectile.new(b.x + b.w / 2 - 10, b.y + b.h / 2 - 6, 1, angle, b)
    set_switch(switch)
    true
  end
end

class Shield < FloatingItem
  def initialize(x, y, args, section, switch)
    set_icon "shield#{args}"
    switch[:extra] = args
    @bomb_type = case args
    when '2' then :amarela
    else          :azul
                 end
    return if check(switch)
    super x + 2, y + 2, 28, 28, "sprite_shield#{args}", nil, 4, 2,
          [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7], 6, @bomb_type
  end

  def update(section)
    super(section) do
      take_anim(section, SB.player.bomb.shielded)
    end
  end

  def use(section, switch)
    b = SB.player.bomb
    return false if b.type != @bomb_type || b.shielded

    b.shielded = true
    set_switch(switch)
    true
  end
end

class Heart < FloatingItem
  def initialize(x, y, args, section)
    args = (args || '1').to_i
    bomb = case args
           when 1 then :vermelha
           when 2 then :verde
           when 3 then :branca
           end
    super x + 2, y + 2, 28, 28, "sprite_heart#{args}", nil, 8, 1,
      [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7], 6, bomb
  end

  def update(section)
    super(section) do
      SB.player.bomb.hp += 1
      SB.play_sound(Res.sound(:getItem))
      StageMenu.play_get_item_effect(@x - section.map.cam.x + @w / 2, @y - section.map.cam.y + @h / 2, :health)
    end
  end
end

class BoardItem < FloatingItem
  def initialize(x, y, args, section, switch)
    set_icon :board
    return if check switch
    super x + 6, y + 3, 20, 26, :sprite_boardItem, Vector.new(-6, -3)
    @item = true
  end

  def update(section)
    super(section) do
      take_anim(section, true)
    end
  end

  def use(section, switch)
    b = SB.player.bomb
    if b.bottom
      @board = Board.new(b.x + (b.facing_right ? 0 : b.w - 50), b.y + b.h - 2, b.facing_right, section, switch)
      section.add(@board)
      set_switch(switch)
      true
    else
      false
    end
  end
end

class Hammer < FloatingItem
  def initialize(x, y, args, section, switch)
    set_icon :hammer
    return if check(switch)
    super x + 7, y + 1, 18, 30, :sprite_hammer, Vector.new(-7, -1)
  end

  def update(section)
    super(section) do
      take_anim(section, true)
    end
  end

  def use(section, switch)
    obj = section.active_object
    if obj.is_a? Board
      obj.take(section)
      set_switch(switch)
      return true
    end
    false
  end
end

class Spring < GameObject
  include Item

  def initialize(x, y, args, section, switch)
    @switch = switch
    @w = 32
    set_icon :spring
    return if check(switch)
    super x, y, 32, 32, :sprite_Spring, Vector.new(-2, -16), 3, 2
    @active_bounds = Rectangle.new x, y - 16, 32, 48
    @start_y = y
    @state = 0
    @timer = 0
    @indices = [0, 4, 4, 5, 0, 5, 0, 5, 0, 5]
    @passable = true
    @ready = false
  end

  def update(section)
    unless @ready
      section.obstacles << self
      @ready = true
    end
    b = SB.player.bomb

    unless SB.stage.stopped == :all
      if b.bottom == self
        reset if @state == 4
        @timer += 1
        if @timer == 10
          case @state
          when 0 then @y += 8; @img_gap.y -= 8; b.y += 8
          when 1 then @y += 6; @img_gap.y -= 6; b.y += 6
          when 2 then @y += 4; @img_gap.y -= 4; b.y += 4
          end
          @state += 1
          set_animation @state
          @timer = 0
        end
      elsif @state > 0 and @state < 4
        reset
      end

      if @state == 4
        animate @indices, 7
        @timer += 1
        b.stored_forces.y = -18 if @timer <= 6
        if @timer == 70
          reset
        elsif @timer == 7
          @y = @start_y
          @img_gap.y = -16
        end
      end
    end

    if b.collide?(self) and SB.key_pressed?(:up)
      take(section, true, @x - section.map.cam.x + @w / 2, @y - section.map.cam.y + @h / 2)
      @dead = true
      section.obstacles.delete self
    end
  end

  def reset
    set_animation 0
    @state = @timer = 0
    @y = @start_y
    @img_gap.y = -16
  end

  def use(section, switch)
    b = SB.player.bomb
    return false if b.bottom.nil?
    x = b.facing_right ? b.x + b.w + @w : b.x - @w
    return false if section.obstacle_at?(x, b.y)
    x -= @w if b.facing_right
    switch[:state] = :normal
    spring = Spring.new(x, (b.y / C::TILE_SIZE).floor * C::TILE_SIZE, nil, section, @switch)
    switch[:obj] = spring
    section.add spring
  end

  def stop_time_immune?
    true
  end

  def draw(map, section)
    super(map, 2, 2)
    if SB.player.bomb.collide?(self)
      Res.img(:fx_Balloon2).draw(@x - map.cam.x, @y - map.cam.y - 40, 0, 2, 2)
    end
  end
end

class Attack2 < FloatingItem
  def initialize(x, y, args, section, switch)
    set_icon :attack2
    if check(switch)
      @bomb_type = :vermelha
      return
    end
    super x + 2, y + 2, 28, 28, :sprite_attack2, nil, 8, 1,
          [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7], 6, :vermelha
  end

  def update(section)
    super(section) do
      take_anim(section, true)
    end
  end

  def use(section, switch)
    b = SB.player.bomb
    return false if b.type != @bomb_type
    section.add Projectile.new(b.x, b.y, 4, 270, b)
    set_switch(switch)
    true
  end
end

class Herb < SBGameObject
  include Item

  def initialize(x, y, args, section, switch)
    set_icon :herb
    return if check(switch)
    super x, y - 4, 30, 36, :sprite_herb, Vector.new(-3, -4)
    @active_bounds = Rectangle.new(x - 3, y - 8, 36, 40)
  end

  def update(section)
    if SB.player.bomb.collide?(self)
      take(section, true, @x - section.map.cam.x + @w / 2, @y - section.map.cam.y + @h / 2)
      @dead = true
    end
  end

  def use(section, switch)
    obj = section.active_object
    if obj.is_a? Monep
      obj.activate(section)
      set_switch(switch)
    end
  end
end

class PuzzlePiece < FloatingItem
  def initialize(x, y, args, section, switch)
    set_icon :puzzlePiece
    @number = args.to_i
    return if check(switch)
    x_off = @number == 2 ? -8 : 0
    y_off = @number == 4 ? -8 : 0
    super(x + x_off, y + y_off, 32, 32, "sprite_puzzlePiece#{@number}")
  end

  def update(section)
    super(section) do
      take_anim(section, true)
    end
  end

  def use(section, switch)
    obj = section.active_object
    if obj.is_a? Puzzle
      obj.add_piece(section, @number)
      set_switch(switch)
    end
  end
end

class JillisStone < FloatingItem
  def initialize(x, y, args, section, switch)
    set_icon :jillisStone
    return if check(switch)
    super(x + 6, y + 6, 20, 20, :sprite_jillisStone, Vector.new(0, -2), 3, 2, [0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5], 7)
  end

  def update(section)
    super(section) do
      take_anim(section, true)
    end
  end

  def use(section, switch)
    obj = section.active_object
    if obj.is_a? MountainBombie
      obj.activate
      set_switch(switch)
    end
  end
end

class Attack3 < FloatingItem
  def initialize(x, y, args, section, switch)
    set_icon :Attack3
    if check(switch)
      @bomb_type = :amarela
      return
    end
    super x + 2, y + 2, 28, 28, :sprite_Attack3, nil, 8, 1,
          [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7], 6, :amarela
  end

  def update(section)
    super(section) do
      take_anim(section, true)
    end
  end

  def use(section, switch)
    b = SB.player.bomb
    return false if b.type != @bomb_type
    b.set_aura(2, 900)
    set_switch(switch)
    true
  end
end

class Attack4 < FloatingItem
  def initialize(x, y, args, section, switch)
    set_icon :attack4
    if check switch
      @bomb_type = :azul
      return
    end
    super x + 2, y + 2, 28, 28, :sprite_attack4, nil, 4, 2,
          [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7], 6, :azul
  end

  def update(section)
    super(section) do
      take_anim(section, true)
    end
  end

  def use(section, switch)
    b = SB.player.bomb
    return false if b.type != @bomb_type
    angle = if b.facing_right; 0
    else; 180;         end
    section.add Projectile.new(b.x + b.w / 2 - 4, b.y + b.h / 2 - 4, 9, angle, b)
    set_switch(switch)
    true
  end
end

class Hourglass < FloatingItem
  include Item

  def initialize(x, y, args, section)
    super x + 2, y + 2, 28, 28, :sprite_hourglass, nil, 8, 1,
          [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7], 6, :branca
  end

  def update(section)
    super(section) do
      SB.player.bomb.reset_cooldown
      SB.play_sound(Res.sound(:getItem))
    end
  end
end

class Attack5 < FloatingItem
  def initialize(x, y, args, section, switch)
    set_icon :attack5
    if check switch
      @bomb_type = :azul
      return
    end
    super x + 2, y + 2, 28, 28, :sprite_attack5, nil, 4, 2,
          [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7], 6, :azul
  end

  def update(section)
    super(section) do
      take_anim(section, true)
    end
  end

  def use(section, switch)
    b = SB.player.bomb
    return false if b.type != @bomb_type
    c_x = b.x + b.w / 2 - 10
    c_y = b.y + b.h / 2 - 5
    (0..7).each do |i|
      angle = i * 45
      section.add(Projectile.new(c_x, c_y, 11, angle, b))
    end
    set_switch(switch)
    true
  end
end

class Star < FloatingItem
  def initialize(x, y, args, section, switch)
    if switch[:state] == :used
      SB.stage.get_star
      return
    end
    super x + 4, y + 4, 24, 24, :sprite_star, Vector.new(-8, -8), 3, 1, [0, 1, 2, 1], 10
  end

  def update(section)
    super(section) do
      switch = SB.stage.find_switch(self)
      use(section, switch)
      StageMenu.play_get_item_effect(@x - section.map.cam.x + @w / 2, @y - section.map.cam.y + @h / 2, :star)
      SB.play_sound(Res.sound(:getItem))
    end
  end

  def use(section, switch)
    SB.stage.get_star
    switch[:state] = :temp_used
  end
end

class Spec < FloatingItem
  def initialize(x, y, args, section, switch)
    return if SB.player.specs.index(SB.stage.id)
    if check(switch)
      SB.stage.set_spec_taken
      return
    end
    super x - 1, y - 1, 34, 34, :sprite_Spec, Vector.new(-12, -12), 2, 2, [0,1,2,3], 5
  end

  def update(section)
    super(section) do
      take(section, false)
    end
    if rand < 0.05
      x = @x + rand(@w) - 7
      y = @y + rand(@h) - 7
      section.add_effect(Effect.new(x, y, :fx_Glow1, 3, 2, 6, [0, 1, 2, 3, 4, 5, 4, 3, 2, 1, 0], 66))
    end
  end

  def use(section, switch)
    SB.player.stage_score += 1000
    SB.stage.set_spec_taken
  end
end
