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
Vector = MiniGL::Vector

############################### classes abstratas ##############################

class Enemy < GameObject
  attr_reader :dying

  def initialize(x, y, w, h, img_gap, sprite_cols, sprite_rows, indices, interval, score, hp = 1)
    super x, y, w, h, "sprite_#{self.class}", img_gap, sprite_cols, sprite_rows

    @indices = indices
    @interval = interval
    @score = score
    @hp = hp
    @control_timer = 0

    @active_bounds = Rectangle.new x + img_gap.x, y + img_gap.y, @img[0].width * 2, @img[0].height * 2
  end

  def set_active_bounds(section)
    t = (@y + @img_gap.y).floor
    r = (@x + @img_gap.x + @img[0].width * 2).ceil
    b = (@y + @img_gap.y + @img[0].height * 2).ceil
    l = (@x + @img_gap.x).floor

    if t > section.size.y
      @dead = true
    elsif r < 0; @dead = true
    elsif b < C::TOP_MARGIN; @dead = true #para sumir por cima, a margem deve ser maior
    elsif l > section.size.x; @dead = true
    else
      if t < @active_bounds.y
        @active_bounds.h += @active_bounds.y - t
        @active_bounds.y = t
      end
      @active_bounds.w = r - @active_bounds.x if r > @active_bounds.x + @active_bounds.w
      @active_bounds.h = b - @active_bounds.y if b > @active_bounds.y + @active_bounds.h
      if l < @active_bounds.x
        @active_bounds.w += @active_bounds.x - l
        @active_bounds.x = l
      end
    end
  end

  def update(section, tolerance = nil)
    if @dying
      @control_timer += 1
      @dead = true if @control_timer == 150
      return if @img_index == @indices[-1]
      animate @indices, @interval
      return
    end

    unless SB.player.dead?
      b = SB.player.bomb
      if b.over?(self, tolerance)
        hit_by_bomb(section)
      elsif b.collide?(self)
        b.hit
      end
      unless @invulnerable
        if b.explode?(self) or section.explode?(self)
          hit_by_explosion(section)
        else
          proj = section.projectile_hit?(self)
          hit_by_projectile(section) if proj && proj != 8
        end
      end
    end

    return if @dying

    if @invulnerable
      @control_timer += 1
      return_vulnerable if @control_timer == C::INVULNERABLE_TIME
    end

    yield if block_given?

    set_active_bounds section
    animate @indices, @interval
  end

  def hit_by_bomb(section)
    SB.player.bomb.bounce(!@invulnerable)
    hit(section, SB.player.bomb.power) unless @invulnerable
  end

  def hit_by_explosion(section)
    @hp = 1
    hit(section)
  end

  def hit_by_projectile(section)
    hit(section)
  end

  def hit(section, amount = 1)
    @hp -= amount
    if @hp <= 0
      SB.player.stage_score += @score
      section.add_score_effect(@x + @w / 2, @y, @score)
      @dying = true
      @indices = [@img.size - 1]
      set_animation @img.size - 1
    else
      get_invulnerable
    end
  end

  def get_invulnerable
    @invulnerable = true
  end

  def return_vulnerable
    @invulnerable = false
    @control_timer = 0
  end

  def is_visible(map)
    @dying || super(map)
  end

  def draw(map = nil, section = nil, scale_x = 2, scale_y = 2, alpha = 0xff, color = 0xffffff, angle = nil, flip = nil, z_index = 0, round = false)
    return if @invulnerable && (@control_timer / 3) % 2 == 0
    if SB.stage.stopped && SB.stage.stop_time_duration < 1_000_000_000
      remaining = SB.stage.stop_time_duration - SB.stage.stopped_timer
      color = 0xff6666 if remaining >= 120 || (remaining / 5) % 2 == 0
    end
    super(map, scale_x, scale_y, alpha, color, angle, flip, z_index, round)
  end
end

class FloorEnemy < Enemy
  def initialize(x, y, args, w, h, img_gap, sprite_cols, sprite_rows, indices, interval, score, speed, hp = 1)
    super x, y, w, h, img_gap, sprite_cols, sprite_rows, indices, interval, score, hp

    @dont_fall = args.nil?
    @speed_m = speed
    @forces = Vector.new -@speed_m, 0
    @facing_right = false
    @turning = false
    @floor_tolerance = 0
  end

  def update(section, tolerance = nil, &block)
    if @invulnerable
      super section
    elsif @turning
      if block_given?
        super(section, tolerance, &block)
      else
        set_direction
        super(section, tolerance)
      end
    else
      super section do
        move(@forces, section.get_obstacles(@x, @y, @w, @h), @dont_fall ? [] : section.ramps)
        @forces.x = 0
        if @left
          prepare_turn :right
        elsif @right
          prepare_turn :left
        elsif @dont_fall
          if @facing_right
            prepare_turn :left unless floor?(section, false)
          elsif not floor?(section, true)
            prepare_turn :right
          end
        elsif @facing_right
          @forces.x = @speed_m if @speed.x == 0
          prepare_turn :left if @speed.x < 0
        else
          @forces.x = -@speed_m if @speed.x == 0
          prepare_turn :right if @speed.x > 0
        end
      end
    end
  end

  def floor?(section, left)
    (0..@floor_tolerance).each do |i|
      return true if section.obstacle_at?(left ? @x - 1 - i : @x + @w + i, @y + @h)
    end
    false
  end

  def prepare_turn(dir)
    @turning = true
    @speed.x = 0
    @next_dir = dir
  end

  def set_direction
    @turning = false
    if @next_dir == :left
      @forces.x = -@speed_m
      @facing_right = false
    else
      @forces.x = @speed_m
      @facing_right = true
    end
  end

  def draw(map, section = nil, color = 0xffffff)
    super(map, section, 2, 2, 255, color, nil, @facing_right ? :horiz : nil)
  end
end

module Boss
  def init(song_id = :boss)
    @activation_x = @x + @w / 2 - C::SCREEN_WIDTH / 2
    @timer = 0
    @state = :waiting
    @speech = SB.text("#{self.class.to_s.downcase}_speech".to_sym)
    @death_speech = SB.text("#{self.class.to_s.downcase}_death".to_sym)
    @song_id = song_id
  end

  def update_boss(section, do_super_update = true, &block)
    if @state == :waiting
      if SB.player.bomb.x >= @activation_x
        section.set_fixed_camera(@x + @w / 2, @y + @h / 2)
        @state = :speaking
      end
    elsif @state == :speaking
      @timer += 1
      if @timer >= 900 or SB.key_pressed?(:confirm)
        section.unset_fixed_camera
        @state = :acting
        @timer = 0
        SB.play_song(Res.song(@song_id))
      end
    else
      if @dying
        @timer += 1
        if @timer >= 600 or SB.key_pressed?(:confirm)
          section.unset_fixed_camera
          section.finish
          @dead = true
        end
        return
      end
      if do_super_update
        super_update(section, &block)
      elsif block_given?
        yield
      end
      if @dying
        section.set_fixed_camera(@x + @w / 2, @y + @h / 2)
        @timer = 0
      end
    end
  end

  def draw_boss
    if @state == :speaking or (@dying and not @dead)
      G.window.draw_quad 5, 495, C::PANEL_COLOR,
                         795, 495, C::PANEL_COLOR,
                         5, 595, C::PANEL_COLOR,
                         795, 595, C::PANEL_COLOR, 1
      SB.text_helper.write_breaking(@state == :speaking ? @speech : @death_speech, 10, 500, 780, :justified, 0, 255, 1)
    end
  end

  def stop_time_immune?
    @state == :speaking
  end
end

################################################################################

class Wheeliam < FloorEnemy
  def initialize(x, y, args, section)
    super x, y, args, 32, 32, Vector.new(-4, -2), 3, 1, [0, 1], 8, 100, 1.6
    @max_speed.y = 10
  end
end

class Sprinny < Enemy
  def initialize(x, y, args, section)
    super x + 3, y, 26, 32, Vector.new(-2, -5), 3, 1, [0, 1], 7, 200

    @leaps = 1000
    @max_leaps = args.to_i
    @facing_right = true
    @indices = [0]
    @idle_timer = 0
  end

  def update(section)
    super(section, 24) do
      forces = Vector.new 0, 0
      if @bottom
        @speed.x = 0
        @indices = [0, 1]
        @idle_timer += 1
        if @idle_timer > 30
          @leaps += 1
          if @leaps > @max_leaps
            @leaps = 1
            @facing_right = !@facing_right
          end
          if @facing_right; forces.x = 3
          else; forces.x = -3; end
          forces.y = -8.5
          @idle_timer = 0
          @indices = [0]
        end
      end
      prev_g = G.gravity.y
      G.gravity.y *= 0.75
      move forces, section.get_obstacles(@x, @y), section.ramps
      G.gravity.y = prev_g
    end
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? :horiz : nil)
  end
end

class Fureel < FloorEnemy
  def initialize(x, y, args, section)
    super x - 4, y - 7, args, 40, 39, Vector.new(-10, 0), 3, 1, [0, 1], 8, 250, 2.3, 2
  end

  def get_invulnerable
    @invulnerable = true
    @indices = [2]
    set_animation 2
  end

  def return_vulnerable
    @invulnerable = false
    @timer = 0
    @indices = [0, 1]
    set_animation 0
  end
end

class Yaw < Enemy
  def initialize(x, y, args, section)
    super x, y, 32, 32, Vector.new(-4, -4), 3, 2, [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 2, 3, 4, 5], 7, 400

    if args.nil?
      @points = [
        Vector.new(@x + 64, @y),
        Vector.new(@x + 96, @y + 32),
        Vector.new(@x + 96, @y + 96),
        Vector.new(@x + 64, @y + 128),
        Vector.new(@x, @y + 128),
        Vector.new(@x - 32, @y + 96),
        Vector.new(@x - 32, @y + 32),
        Vector.new(@x, @y)
      ]
      @speed_m = 3
      tr_dist = 10.66
    else
      @x -= 6
      @y -= 6
      @w = @h = 44
      @img = Res.imgs(:sprite_Yawnster, 3, 2)
      @img_gap = Vector.new(-6, -6)
      @score = 440
      @points = [
        Vector.new(@x + 128, @y + 128),
        Vector.new(@x + 192, @y + 64),
        Vector.new(@x + 128, @y),
        Vector.new(@x, @y + 128),
        Vector.new(@x - 64, @y + 64),
        Vector.new(@x, @y)
      ]
      @speed_m = 4
      tr_dist = 10
    end

    min_x = max_x = @x
    min_y = max_y = @y
    @track = []
    @points.each_with_index do |p, i|
      min_x = p.x if p.x < min_x
      max_x = p.x if p.x > max_x
      min_y = p.y if p.y < min_y
      max_y = p.y if p.y > max_y
      n_p = i == @points.size - 1 ? @points[0] : @points[i + 1]
      d_x = n_p.x - p.x; d_y = n_p.y - p.y
      d = Math.sqrt(d_x**2 + d_y**2)
      amount = (d / tr_dist).to_i
      ratio = tr_dist / d
      (0...amount).each do |j|
        @track << [p.x + j * ratio * d_x - 1 + @w / 2, p.y + j * ratio * d_y - 1 + @h / 2,
                   p.x + j * ratio * d_x + 1 + @w / 2, p.y + j * ratio * d_y - 1 + @h / 2,
                   p.x + j * ratio * d_x - 1 + @w / 2, p.y + j * ratio * d_y + 1 + @h / 2,
                   p.x + j * ratio * d_x + 1 + @w / 2, p.y + j * ratio * d_y + 1 + @h / 2]
      end
    end

    @active_bounds = Rectangle.new(min_x, min_y, max_x - min_x + @w, max_y - min_y + @h)
  end

  def update(section)
    super section do
      cycle @points, @speed_m
    end
  end

  def hit_by_bomb(section)
    SB.player.bomb.hit
  end

  def hit_by_projectile(section); end

  def draw(map, section)
    @track.each do |t|
      G.window.draw_quad(t[0] - map.cam.x, t[1] - map.cam.y, 0xffffffff,
                         t[2] - map.cam.x, t[3] - map.cam.y, 0xffffffff,
                         t[4] - map.cam.x, t[5] - map.cam.y, 0xffffffff,
                         t[6] - map.cam.x, t[7] - map.cam.y, 0xffffffff, 0)
    end
    super(map)
  end
end

class Ekips < GameObject
  def initialize(x, y, args, section)
    super x + 5, y - 10, 22, 25, :sprite_Ekips, Vector.new(-37, -8), 2, 3

    @act_timer = 0
    @active_bounds = Rectangle.new x - 32, y - 18, 96, 50
    @attack_bounds = Rectangle.new x - 26, y + 10, 84, 12
    @score = 160
  end

  def update(section)
    b = SB.player.bomb
    if b.explode?(self) || section.projectile_hit?(self) && !@attacking
      SB.player.stage_score += @score
      section.add_score_effect(@x + @w / 2, @y, @score)
      @dead = true
      return
    end

    if b.over? self
      if @attacking
        b.bounce
        SB.player.stage_score += @score
        section.add_score_effect(@x + @w / 2, @y, @score)
        @dead = true
        return
      else
        b.hit
      end
    elsif @attacking and b.bounds.intersect? @attack_bounds
      b.hit
    elsif b.collide? self
      b.hit
    end

    @act_timer += 1
    if @preparing and @act_timer >= 60
      animate [2, 3, 4, 5], 5
      if @img_index == 5
        @attacking = true
        @preparing = false
        set_animation 5
        @act_timer = 0
      end
    elsif @attacking and @act_timer >= 150
      animate [4, 3, 2, 1, 0], 5
      if @img_index == 0
        @attacking = false
        set_animation 0
        @act_timer = 0
      end
    elsif @act_timer >= 150
      @preparing = true
      set_animation 1
      @act_timer = 0
    end
  end

  def dying; false; end

  def draw(map, section)
    color = 0xffffff
    if SB.stage.stopped && SB.stage.stop_time_duration < 1_000_000_000
      remaining = SB.stage.stop_time_duration - SB.stage.stopped_timer
      color = 0xff6666 if remaining >= 120 || (remaining / 5) % 2 == 0
    end
    super(map, 2, 2, 255, color)
  end
end

class Faller < GameObject
  def initialize(x, y, args, section)
    super x, y, 32, 12, :sprite_Faller, Vector.new(-1, 0), 4, 1
    @range = args.to_i
    @start = Vector.new x, y
    @up = Vector.new x, y - @range * 32
    @active_bounds = Rectangle.new x, @up.y, 32, (@range + 1) * 32
    @passable = true
    section.obstacles << self

    @bottom = Block.new x, y + 20, 32, 12, false
    @bottom_img = Res.img :sprite_Faller2
    section.obstacles << @bottom

    @indices = [0, 1, 2, 3, 2, 1]
    @interval = 8
    @step = 0
    @act_timer = 0
    @score = 300
  end

  def update(section)
    b = SB.player.bomb
    if b.explode? self
      SB.player.stage_score += @score
      section.add_score_effect(@x + @w / 2, @y, @score)
      section.obstacles.delete self
      section.obstacles.delete @bottom
      @dead = true
      return
    elsif b.bottom == @bottom
      b.hit
    elsif b.bounds.intersect?(Rectangle.new(@x, @y + 12, @w, 2))
      b.hit
    end

    animate @indices, @interval

    if @step == 0 or @step == 2 # parado
      @act_timer += 1
      if @act_timer >= 90
        @step += 1
        @act_timer = 0
      end
    elsif @step == 1 # subindo
      move_carrying @up, 1, [b], section.get_obstacles(b.x, b.y), section.ramps
      @step += 1 if @speed.y == 0
    else # descendo
      diff = ((@start.y - @y) / 5).ceil
      move_carrying @start, diff, [b], section.get_obstacles(b.x, b.y), section.ramps
      @step = 0 if @speed.y == 0
    end
  end

  def dying; false; end

  def draw(map, section)
    color = 0xffffffff
    if SB.stage.stopped && SB.stage.stop_time_duration < 1_000_000_000
      remaining = SB.stage.stop_time_duration - SB.stage.stopped_timer
      color = 0xffff6666 if remaining >= 120 || (remaining / 5) % 2 == 0
    end
    @img[@img_index].draw @x - map.cam.x, @y - map.cam.y, 0, 2, 2, color
    @bottom_img.draw @x - map.cam.x, @start.y + 15 - map.cam.y, 0, 2, 2, color
  end
end

class Turner < Enemy
  def initialize(x, y, args, section)
    super x + 2, y - 7, 60, 39, Vector.new(-2, -25), 3, 2, [0, 1, 2, 1], 8, 300
    @harmful = true
    @passable = true
    @speed_m = 1.5

    @aim1 = Vector.new(@x, @y)
    while not section.obstacle_at? @aim1.x - 3, @aim1.y and
      not section.obstacle_at? @aim1.x - 3, @aim1.y + 8 and
      section.obstacle_at? @aim1.x - 3, @y + @h
      @aim1.x -= C::TILE_SIZE
    end

    @aim2 = Vector.new(@x, @y)
    while not section.obstacle_at? @aim2.x + 63, @aim2.y and
      not section.obstacle_at? @aim2.x + 63, @aim2.y + 8 and
      section.obstacle_at? @aim2.x + 63, @y + @h
      @aim2.x += C::TILE_SIZE
    end

    @obst = section.obstacles
  end

  def update(section)
    @harm_bounds = Rectangle.new @x, @y - 23, 60, 62
    super section do
      if @harmful
        SB.player.bomb.hit if SB.player.bomb.bounds.intersect? @harm_bounds
        move_free @aim1, @speed_m
        if @speed.x == 0 and @speed.y == 0
          @harmful = false
          @indices = [3, 4, 5, 4]
          set_animation 3
          @obst << self
        end
      else
        b = SB.player.bomb
        move_carrying @aim2, @speed_m, [b], section.get_obstacles(b.x, b.y), section.ramps
        if @speed.x == 0 and @speed.y == 0
          @harmful = true
          @indices = [0, 1, 2, 1]
          set_animation 0
          @obst.delete self
        end
      end
    end
  end

  def hit_by_bomb(section); end

  def hit_by_explosion
    SB.player.stage_score += @score
    @obst.delete self unless @harmful
    @dead = true
  end
end

class Chamal < Enemy
  include Boss
  alias :super_update :update

  X_OFFSET = 224
  WALK_AMOUNT = 96

  def initialize(x, y, args, section)
    super x - 25, y - 74, 82, 106, Vector.new(-16, -8), 3, 1, [0, 1, 0, 2], 7, 1000, 3
    @left_limit = @x - X_OFFSET
    @right_limit = @x + X_OFFSET
    @spawn_points = [
      Vector.new(@x + @w / 2 - 40, @y - 400),
      Vector.new(@x + @w / 2 + 80, @y - 400),
      Vector.new(@x + @w / 2 + 200, @y - 400)
    ]
    @spawns = []
    @turn = 2
    @speed_m = 3
    @facing_right = false
    init
  end

  def update(section)
    update_boss(section) do
      if @moving
        move_free @aim, @speed_m
        if @speed.x == 0 and @speed.y == 0
          @moving = false
          @timer = 0
        end
      else
        @timer += 1
        if @timer == 120
          if @facing_right
            if @x >= @right_limit
              x = @x - WALK_AMOUNT
              @facing_right = false
            else
              x = @x + WALK_AMOUNT
            end
          elsif @x <= @left_limit
            x = @x + WALK_AMOUNT
            @facing_right = true
          else
            x = @x - WALK_AMOUNT
          end
          @aim = Vector.new x, @y
          @moving = true
          if @spawns.size == 0
            @turn += 1
            if @turn == 3
              @spawn_points.each do |p|
                @spawns << Wheeliam.new(p.x, p.y, '!', section)
                section.add(@spawns[-1])
              end
              @respawned = true
            end
          end
        end
      end
      if @spawns.all?(&:dead?) && @respawned && @gun_powder.nil?
        @spawns = []
        @respawned = false
        @gun_powder = GunPowder.new(@x, @y + 74, nil, section, nil)
        section.add(@gun_powder)
        section.add_effect(Effect.new(@x - 14, @y + 10, :fx_arrow, 3, 1, 8, [0, 1, 2, 1], 300))
        @turn = 0
      end
      @gun_powder = nil if @gun_powder && @gun_powder.dead?
    end
  end

  def hit_by_bomb(section)
    SB.player.bomb.bounce(false)
  end

  def hit_by_explosion(section)
    hit(section)
    @speed_m = 4 if @hp == 1
    @moving = false
    @timer = -C::INVULNERABLE_TIME
  end

  def get_invulnerable
    super
    @indices = [0]
    set_animation 0
  end

  def return_vulnerable
    super
    @indices = [0, 1, 0, 2]
    set_animation 0
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? :horiz : nil)
    draw_boss
  end
end

class Electong < Enemy
  def initialize(x, y, args, section)
    super x - 12, y - 11, 56, 43, Vector.new(-4, -91), 4, 2, [0, 1, 2, 1], 7, 250, 1
    @timer = 0
    @tongue_y = @y
  end

  def hit_by_bomb(section)
    SB.player.bomb.hit
  end

  def update(section)
    super(section) do
      b = SB.player.bomb
      if @will_attack
        @tongue_y -= 91 / 14.0
        if @img_index == 5
          @indices = [5, 6, 7, 6]
          @attacking = true
          @will_attack = false
          @tongue_y = @y - 91
        end
      elsif @attacking
        @timer += 1
        if @timer == 60
          @indices = [4, 3, 0]
          set_animation 4
          @attacking = false
        end
      elsif @timer > 0
        @tongue_y += 91 / 14.0
        if @img_index == 0
          @indices = [0, 1, 2, 1]
          @timer = -60
          @tongue_y = @y
        end
      else
        @timer += 1 if @timer < 0
        if @timer == 0 and b.x + b.w > @x - 40 and b.x < @x + @w + 40
          @indices = [3, 4, 5]
          set_animation 3
          @will_attack = true
        end
      end
      if b.bounds.intersect? Rectangle.new(@x + 22, @tongue_y, 12, @y + @h - @tongue_y)
        b.hit
      end
    end
  end
end

class Chrazer < Enemy
  def initialize(x, y, args, section)
    super x + 1, y - 11, 30, 43, Vector.new(-21, -20), 2, 2, [0, 1, 0, 2], 7, 500, 2
    @facing_right = false
  end

  def update(section)
    super(section) do
      forces = Vector.new(0, 0)
      unless @invulnerable
        d = SB.player.bomb.x - @x
        d = 150 if d > 150
        d = -150 if d < -150
        if @bottom
          forces.x = d * 0.01666667
          forces.y = -12.5
          if d > 0 and not @facing_right
            @facing_right = true
          elsif d < 0 and @facing_right
            @facing_right = false
          end
          @speed.x = 0
        else
          forces.x = d * 0.001
        end
      end
      move forces, section.get_obstacles(@x, @y), section.ramps
    end
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? :horiz : nil)
  end
end

class Robort < FloorEnemy
  def initialize(x, y, args, section)
    super x - 12, y - 31, args, 56, 63, Vector.new(-14, -9), 3, 2, [0, 1, 2, 1], 6, 450, 2.2, 3
  end

  def update(section)
    super(section) do
      @timer += 1
      if @timer == 90
        @indices = [0, 1, 2, 1]
        @interval = 7
        set_direction
      end
    end
  end

  def prepare_turn(dir)
    @indices = [3, 4, 5, 4]
    @interval = 4
    @timer = 0
    super(dir)
  end

  def hit_by_bomb(section)
    if @turning
      SB.player.bomb.hit
    else
      super(section)
    end
  end
end

class Shep < FloorEnemy
  def initialize(x, y, args, section)
    super x, y, args, 42, 32, Vector.new(-5, -2), 3, 2, [0, 1, 0, 2], 7, 160, 2
  end

  def update(section)
    super(section) do
      @timer += 1
      if @timer == 35
        section.add(Projectile.new(@facing_right ? @x + @w - 4 : @x - 4, @y + 10, 2, @facing_right ? 0 : 180, self))
        @indices = [0, 1, 0, 2]
        set_animation(@indices[0])
        set_direction
      end
    end
  end

  def prepare_turn(dir)
    @timer = 0
    @indices = [0, 3, 4, 5, 5]
    set_animation @indices[0]
    super(dir)
  end
end

class Flep < Enemy
  def initialize(x, y, args, section)
    super x, y, 64, 20, Vector.new(0, 0), 1, 3, [0, 1, 2], 6, 250, 2
    @movement = C::TILE_SIZE * args.to_i
    @aim = Vector.new(@x - @movement, @y)
    @facing_right = false
  end

  def update(section)
    if @invulnerable
      super(section)
    else
      super(section) do
        move_free @aim, 2.5
        if @speed.x == 0 and @speed.y == 0
          @aim = Vector.new(@x + (@facing_right ? -@movement : @movement), @y)
          @facing_right = !@facing_right
        end
      end
    end
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? :horiz : nil)
  end
end

class Jellep < Enemy
  def initialize(x, y, args, section)
    super x, section.size.y - 1, 32, 110, Vector.new(-5, 0), 3, 1, [0, 1, 0, 2], 5, 500
    @max_y = y
    @state = 0
    @timer = 0
    @active_bounds.y = y
    @water = args.nil?
  end

  def update(section)
    super(section) do
      if @state == 0
        @timer += 1
        if @timer == 60
          @stored_forces.y = -14
          @state = 1
          @timer = 0
        end
      else
        force = @y - @max_y <= 100 ? 0 : -G.gravity.y
        move Vector.new(0, force), [], []
        if @state == 1 and @speed.y >= 0
          @state = 2
        elsif @state == 2 and @y >= section.size.y
          @speed.y = 0
          @y = section.size.y - 1
          @state = 0
        end
        @prev_water = @water
        @water = section.element_at(Water, @x, @y)
        if @water && !@prev_water || @prev_water && !@water
          section.add_effect(Effect.new(@x - 16, (@water || @prev_water).y - 19, :fx_water, 1, 4, 8, nil, nil, :splash))
        end
      end
    end
  end

  def hit_by_bomb(section)
    b = SB.player.bomb
    if b.power > 1
      b.bounce
      hit(section)
    else
      b.hit
    end
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @state == 2 ? :vert : nil)
  end
end

class Snep < Enemy
  def initialize(x, y, args, section)
    super x, y - 24, 32, 56, Vector.new(0, 4), 5, 2, [0, 1, 0, 2], 12, 200
    @facing_right = args.nil?
  end

  def update(section)
    super(section) do
      b = SB.player.bomb
      if b.y + b.h > @y && b.y + b.h <= @y + @h &&
         (@facing_right && b.x > @x && b.x < @x + @w + 22 || !@facing_right && b.x < @x && b.x + b.w > @x - 22)
        if @attacking
          b.hit if @img_index == 8
        else
          @attacking = true
          @indices = [6, 7, 8, 7, 6, 0]
          @interval = 4
          set_animation 6
        end
      end

      if @attacking && @img_index == 0
        @attacking = false
        @indices = [0, 1, 0, 2]
        @interval = 12
        set_animation 0
      end
    end
  end

  def hit_by_bomb(section)
    SB.player.bomb.hit
    @attacking = true
    @indices = [3, 4, 5, 4, 3, 0]
    @interval = 4
    set_animation 3
  end

  def hit(section)
    super
    if @dying
      @indices = [9]
      set_animation 9
    end
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? nil : :horiz)
  end
end

class Vamep < Enemy
  def initialize(x, y, args, section)
    super x, y, 29, 22, Vector.new(-24, -18), 2, 2, [0, 1, 2, 3, 2, 1], 6, 150
    @angle = 0
    if args
      args = args.split ','
      @radius = args[0].to_i * C::TILE_SIZE
      @speed = (args[1] || '3').to_f
    else
      @radius = C::TILE_SIZE
      @speed = 3
    end
    @start_x = x
    @start_y = y
  end

  def update(section)
    super(section) do
      radians = @angle * Math::PI / 180
      @x = @start_x + Math.cos(radians) * @radius
      @y = @start_y + Math.sin(radians) * @radius
      @angle += @speed
      @angle %= 360 if @angle >= 360
    end
  end
end

class Armep < FloorEnemy
  def initialize(x, y, args, section)
    super(x, y + 12, args, 41, 20, Vector.new(-21, -3), 1, 4, [0, 1, 0, 2], 8, 300, 1.3)
  end

  def hit_by_bomb(section)
    b = SB.player.bomb
    if b.power > 1
      b.bounce
      hit(section)
    else
      b.hit
    end
  end

  def hit_by_projectile(section); end
end

class Owlep < Enemy
  def initialize(x, y, args, section)
    y -= 50 if args.nil?
    super x - 3, y - 32, 38, 55, Vector.new(-3, 0), 4, 1, [0, 0, 1, 0, 0, 0, 2], 60, 250, 2
  end

  def update(section)
    super(section) do
      b = SB.player.bomb
      if !@attacking && b.x + b.w > @x && b.x < @x + @w && b.y > @y + @h && b.y < @y + C::SCREEN_HEIGHT
        section.add(Projectile.new(@x + 10, @y + 10, 3, 90, self))
        section.add(Projectile.new(@x + 20, @y + 10, 3, 90, self))
        @indices = [0]
        set_animation 0
        @attacking = true
        @timer = 0
      elsif @attacking
        @timer += 1
        if @timer == 60
          @indices = [0, 0, 1, 0, 0, 0, 2]
          set_animation 0
          @attacking = false
        end
      end
    end
  end
end

class Zep < Enemy
  def initialize(x, y, args, section)
    super x, y - 18, 60, 50, Vector.new(-38, -30), 3, 2, [0, 1, 2, 3, 4, 5], 5, 400, 3
    @passable = true

    @aim1 = Vector.new(@x, @y)
    while !section.obstacle_at?(@aim1.x - 3, @y) &&
      !section.obstacle_at?(@aim1.x - 3, @y + 18) &&
      !section.obstacle_at?(@aim1.x - 3, @y + 17 + C::TILE_SIZE) &&
      section.obstacle_at?(@aim1.x - 3, @y + @h)
      @aim1.x -= C::TILE_SIZE
    end

    @aim2 = Vector.new(@x, @y)
    while !section.obstacle_at?(@aim2.x + 65, @y) &&
      !section.obstacle_at?(@aim2.x + 65, @y + 18) &&
      !section.obstacle_at?(@aim2.x + 65, @y + 17 + C::TILE_SIZE) &&
      section.obstacle_at?(@aim2.x + 65, @y + @h)
      @aim2.x += C::TILE_SIZE
    end
    @aim2.x += 4

    @aim = @aim1
    section.obstacles << self
  end

  def update(section)
    super section do
      b = SB.player.bomb
      move_carrying @aim, 4, [b], section.get_obstacles(b.x, b.y), section.ramps
      if @speed.x == 0 and @speed.y == 0
        @aim = @aim == @aim1 ? @aim2 : @aim1
        @img_gap.x = @aim == @aim2 ? -16 : -24
      end
    end
  end

  def hit_by_bomb(section); end

  def hit(section)
    super
    if @dying
      section.obstacles.delete self
      @indices = [5]
      set_animation 5
    end
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @aim == @aim1 ? nil : :horiz)
  end
end

class Butterflep < Enemy
  def initialize(x, y, args, section)
    super(x - 12, y - 12, 56, 54, Vector.new(-4, -4), 2, 2, [0, 1, 2, 1], 10, 250)
    @speed_m = 5
    ps = args.split(':')
    @points = []
    ps.each do |p|
      pp = p.split(',')
      @points << Vector.new(pp[0].to_i * C::TILE_SIZE - 12, pp[1].to_i * C::TILE_SIZE - 12)
    end
    @points << Vector.new(@x, @y)
    @timer = 0
  end

  def update(section)
    super(section) do
      if @moving
        cycle(@points, @speed_m)
        if @speed.x == 0 and @speed.y == 0
          @moving = false
          @timer = 0
        end
      else
        @timer += 1
        @moving = true if @timer == 60
      end
    end
  end

  def hit_by_bomb(section)
    b = SB.player.bomb
    if b.power > 1
      b.bounce
      hit(section)
    else
      b.hit
    end
  end
end

class Sahiss < FloorEnemy
  include Boss
  alias :super_update :update

  def initialize(x, y, args, section)
    super x - 54, y - 148, args, 148, 180, Vector.new(-139, -3), 2, 3, [0, 1, 0, 2], 7, 2000, 3, 4
    @time = 180 + rand(240)
    init
  end

  def update(section)
    update_boss(section, false) do
      obj = section.active_object
      if obj && !obj.dying && obj.bounds.intersect?(bounds)
        hit(section)
        next
      end

      if @attacking
        move_free @aim, 6
        b = SB.player.bomb
        if b.over? self
          b.bounce(false)
        elsif b.collide? self
          b.hit
        elsif @img_index == 5
          r = Rectangle.new(@x + 170, @y, 1, 120)
          b.hit if b.bounds.intersect? r
        end
        if @speed.x == 0
          if @img_index == 5
            set_bounds 3
            @img_index = 4
          end
          @timer += 1
          if @timer == 5
            set_bounds 4
            @img_index = 0
          elsif @timer == 60
            @img_index = 0
            @stored_forces.x = -3
            @attacking = false
            @timer = 0
            @time = 180 + rand(240)
          end
        elsif @img_index == 4
          @timer += 1
          if @timer == 5
            set_bounds 2
            @img_index = 5
            @timer = 0
          end
        end
      end
    end
    if @state == :acting and not @attacking and not @dying
      prev = @facing_right
      super_update(section) unless @timer >= @time
      if @dead
        section.finish
      elsif @aim
        @timer += 1
        if @timer == @time
          if @facing_right
            @timer = @time - 1
          else
            set_animation(1)
          end
        elsif @timer == @time + 60
          set_bounds 1
          @attacking = true
          @img_index = 4
          @timer = 0
        end
      elsif @facing_right and not prev
        @aim = Vector.new(@x, @y)
      end
    end
  end

  def set_bounds(step)
    @x += case step; when 1 then -55; when 2 then -74; else 0; end
    @y += case step; when 1 then 16; when 2 then 60; when 3 then -60; else -16; end
    @aim.y += case step; when 1 then 16; when 2 then 60; when 3 then -60; else -16; end
    @w = case step; when 1 then 137; when 2 then 170; when 3 then 137; else 148; end
    @h = case step; when 1 then 164; when 2 then 70; when 3 then 164; else 180; end
    @img_gap.x = case step; when 1 then -84; when 2 then -10; when 3 then -84; else -139; end
    @img_gap.y = case step; when 1 then -19; when 2 then -64; when 3 then -19; else -3; end
  end

  def hit_by_bomb(section)
    SB.player.bomb.bounce(false)
  end

  def hit_by_projectile(section); end

  def hit(section)
    unless @invulnerable
      super
      SB.play_sound(Res.sound(:stomp))
      if @hp > 0
        if @img_index == 5
          set_bounds 3; set_bounds 4
        elsif @img_index == 4
          set_bounds 4
        end
        @attacking = false
        @timer = 0
        @time = 180 + rand(240)
      end
      if @hp == 2
        section.activate_object(StalactiteGenerator, 0)
      end
      @indices = [3]
      set_animation 3
    end
  end

  def return_vulnerable
    super
    @indices = [0, 1, 0, 2]
    set_animation 0
  end

  def draw(map, section)
    super(map)
    draw_boss
  end
end

class Forsby < Enemy
  def initialize(x, y, args, section)
    args = ',' if args.nil? || args.empty?
    args = args.split(',', -1)
    super x - 8, y - 22, 48, 54, Vector.new(-11, -6), 2, 3, [0, 1, 0, 2], 15, 250, 2
    @facing_right = !args[0].empty?
    if args[1] && !args[1].empty?
      @img = Res.imgs(:sprite_Morsby, 2, 3)
      @img_gap.y = -10
      @score = 320
      @intervals = [45, 60, 75]
      @proj_type = 10
    else
      @intervals = [120, 180, 210]
      @proj_type = 5
    end
    @state = @timer = 0
  end

  def update(section)
    super(section) do
      @timer += 1
      if @state == 0 && @timer > @intervals[0]
        @indices = [3]
        set_animation 3
        @state = 1
      elsif @state == 1 && @timer > @intervals[1]
        @indices = [4]
        set_animation 4
        section.add(Projectile.new(@facing_right ? @x + @w - 16 : @x - 5, @y + 14, @proj_type, @facing_right ? 0 : 180, self))
        @state = 2
      elsif @state == 2 && @timer > @intervals[2]
        @indices = [0, 1, 0, 2]
        set_animation 0
        @state = @timer = 0
      end
    end
    if @dying
      @indices = [5]
      set_animation 5
    end
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? nil : :horiz)
  end
end

class Stilty < FloorEnemy
  def initialize(x, y, args, section)
    super(x + 6, y - 26, args, 20, 58, Vector.new(-6, -42), 5, 2, [0, 1, 0, 2], 7, 300, 2, 2)
  end

  def update(section)
    if @rising
      animate @indices, @interval
      if @img_index == 6
        @y -= 40; @h += 40
        @img_gap.y = -2
        @speed_m = 3
        if @speed.x < 0
          @speed.x = -3
        elsif @speed.x > 0
          @speed.x = 3
        end
        @indices = [6, 7, 6, 8]
        set_animation 6
        @rising = false
      end
    else
      super(section, 20)
    end
  end

  def hit(section, amount = 1)
    super
    @indices = (@hp == 0 ? [9] : [3])
    set_animation(@hp == 0 ? 9 : 3)
  end

  def return_vulnerable
    super
    @rising = true
    @indices = [0, 4, 0, 4, 5, 4, 5, 6]
    set_animation 0
  end
end

class Mantul < FloorEnemy
  def initialize(x, y, args, section)
    super(x - 10, y - 24, args, 52, 56, Vector.new(-6, -8), 2, 2, [0, 1, 0, 2], 7, 300, 1.5, 2)
    @timer = 0
  end

  def update(section)
    super(section)
    return if @dying or @invulnerable
    @timer += 1
    if @timer == 180
      section.add(Projectile.new(@x + 48, @y + 30, 2, 0, self))
      section.add(Projectile.new(@x - 4, @y + 30, 2, 180, self))
      section.add(Projectile.new(@x + 10, @y, 2, 240, self))
      section.add(Projectile.new(@x + 34, @y, 2, 300, self))
      @timer = 0
    end
  end
end

class Lambul < FloorEnemy
  def initialize(x, y, args, section)
    super(x - 4, y - 38, args, 30, 70, Vector.new(-50, -10), 4, 2, [0, 1, 0, 2], 7, 300, 2)
  end

  def update(section)
    b = SB.player.bomb
    if @dying
      super
    elsif @attacking
      @timer += 1
      if @timer == 80
        @attacking = false
        set_animation 0
      elsif @timer >= 60
        animate [6, 5, 4, 3], 5
      elsif @timer >= 20
        r = Rectangle.new(@facing_right ? @x : @x - 48, @y + 40, 88, 30)
        b.hit if b.bounds.intersect?(r)
      else
        animate [3, 4, 5, 6], 5
      end
    elsif !SB.player.dead? && b.y + b.h >= @y + @h - 10 && b.y + b.h < @y + @h + 10 && (b.x + b.w/2 - @x - @w/2).abs <= 80 && (b.x < @x && !@facing_right || b.x > @x && @facing_right)
      @x += @facing_right ? 10 : -10
      @attacking = true
      @timer = 0
      set_animation 3
    else
      super
    end
  end

  def hit_by_bomb(section)
    hit(section) if SB.player.bomb.power > 1
  end
end

class Icel < Enemy
  def initialize(x, y, args, section)
    super x - 4, y + 2, 40, 28, Vector.new(-4, -4), 2, 3, [0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5], 7, 250
    @radius = (args || 2).to_i * C::TILE_SIZE
    @timer = @angle = 0
    @state = 3
    @center = Vector.new(@x + @w/2, @y + @h/2)
  end

  def update(section)
    super(section) do
      @timer += 1
      if @timer == 120
        @eff1 = section.add_effect(Ice.new(@center.x + @radius, @center.y))
        @eff2 = section.add_effect(Ice.new(@center.x - @radius, @center.y))
      elsif @timer == 240
        @eff1 = @eff2 = nil
        @timer = @angle = 0
      elsif @timer > 120
        @angle += Math::PI / 60
        x_off = @radius * Math.cos(@angle)
        y_off = @radius * Math.sin(@angle)
        @eff1.move(@center.x + x_off, @center.y - y_off)
        @eff2.move(@center.x - x_off, @center.y + y_off)
      end

      if @timer % 10 == 0
        if @state == 0 or @state == 1; @y -= 1
        else; @y += 1; end
        @state += 1
        @state = 0 if @state == 4
      end
    end
  end

  def hit_by_bomb(section); end
end

class Ignel < Enemy
  def initialize(x, y, args, section)
    super x + 4, y - 16, 24, 48, Vector.new(-2, -12), 3, 1, [0, 1, 2], 5, 250
    @radius = (args || 4).to_i
    @timer = 0
    @center = Vector.new(@x + @w/2, @y + @h)
  end

  def update(section)
    super(section) do
      @timer += 1
      if @timer == 120
        (1..@radius).each do |i|
          section.add_effect(Fire.new(@center.x + i * C::TILE_SIZE, @center.y))
          section.add_effect(Fire.new(@center.x - i * C::TILE_SIZE, @center.y))
        end
      elsif @timer == 240
        @timer = 0
      end
    end
  end

  def hit_by_bomb(section)
    SB.player.bomb.hit
  end

  def hit_by_explosion(section); end
end

class Warclops < Enemy
  def initialize(x, y, args, section)
    super x - 19, y - 84, 70, 116, Vector.new(-10, -4), 2, 2, [0, 1, 0, 2], 9, 750, 3
  end

  def update(section)
    super(section) do
      forces = Vector.new(0, 0)
      unless @invulnerable
        b = SB.player.bomb
        d = b.x + b.w/2 - @x - @w/2
        d = 150 if d > 150
        d = -150 if d < -150
        forces.x = d * 0.01666667
        if d > 0 and not @facing_right
          @facing_right = true
        elsif d < 0 and @facing_right
          @facing_right = false
        end
        @speed.x = 0
      end
      move forces, section.get_obstacles(@x, @y, @w, @h), section.ramps
    end
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? :horiz : nil)
  end

  def hit_by_bomb(section)
    b = SB.player.bomb
    b.bounce(b.power > 1)
    hit(section) if b.power > 1
  end

  def hit_by_explosion(section)
    @hp -= 1
    hit(section)
  end
end

class Necrul < FloorEnemy
  def initialize(x, y, args, section)
    super(x - 20, y - 32, nil, 72, 64, Vector.new(-34, -10), 2, 3, [1,0,1,2], 7, 330, 2, 2)
  end

  def update(section)
    super(section) do
      @timer += 1
      if @timer % 28 == 0
        section.add(Projectile.new(@facing_right ? @x + @w + 30 : @x - 30, @y + 34, 6, @facing_right ? 0 : 180, self))
        if @timer == 112
          @indices = [1, 0, 1, 2]
          set_animation(@indices[0])
          set_direction
        elsif @timer == 56
          @facing_right = !@facing_right
        end
      end
    end
  end

  def prepare_turn(dir)
    @timer = 0
    @indices = [1, 3, 4, 3]
    set_animation @indices[0]
    super(dir)
  end
end

class Ulor < FloorEnemy
  include Boss

  alias :super_update :update

  def initialize(x, y, args, section)
    super(x - 34, y - 88, args, 100, 120, Vector.new(-20, -8), 2, 2, [0, 1, 0, 2], 7, 2400, 3, 5)
    @timer = 0
    @state = :walking
    @spawn_point = Vector.new(x - 12 * C::TILE_SIZE, y - 9 * C::TILE_SIZE)
    init
  end

  def update(section)
    update_boss(section, false) do
      @attack_time = 180 + rand(120) if @attack_time.nil?
      @timer += 1
      if @state == :preparing
        if @timer == 90
          set_animation(3)
          (1..25).each do |i|
            section.activate_object(Stalactite, i)
          end
          @spawned = false
          @timer = 0
          @state = :attacking
        end
        if @timer % 10 == 0
          @x += 5
        elsif @timer % 5 == 0
          @x -= 5
        end
      elsif @state == :attacking
        if @timer == (@hp < 3 ? 60 : 120)
          set_animation(0)
          @timer = 0
          @state = :walking
        end
      else
        super_update(section)
        unless @spawned
          (0..24).each do |i|
            section.add(Stalactite.new(@spawn_point.x + i * C::TILE_SIZE, @spawn_point.y, "2,!,#{i + 1}", section))
          end
          @spawned = true
        end
        if @timer == @attack_time
          set_animation(0)
          @timer = 0
          @attack_time = nil
          @state = :preparing
        end
      end

      if @state != :walking
        unless SB.player.dead?
          b = SB.player.bomb
          if b.over?(self, nil)
            hit_by_bomb(section)
          elsif b.collide?(self)
            b.hit
          end
        end
      end
    end
  end

  def hit_by_bomb(section)
    can_hit = @state == :attacking && !@invulnerable
    SB.player.bomb.bounce(can_hit)
    if can_hit
      hit(section, 1)
      if @hp < 3
        @speed_m = 4
        @speed.x = (@speed.x <=> 0) * 4
      end
      @state = :walking
    end
  end

  def hit_by_projectile(section); end

  def draw(map, section)
    super(map, section, @hp < 3 ? 0xff9999 : 0xffffff)
    draw_boss
  end
end

class Umbrex < FloorEnemy
  RANGE = 10

  def initialize(x, y, args, section)
    super(x, y - 118, args, 64, 150, Vector.new(-48, -10), 4, 2, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 1], 7, 250, 3)
    @hop_timer = 0
  end

  def update(section)
    b = SB.player.bomb
    if @dying
      super(section)
    elsif @attacking
      @timer += 1
      if @timer == 80
        set_animation(0)
        @attacking = false
      elsif @timer < 20
        animate([3, 4, 5, 6], 5)
      elsif @timer >= 60
        animate([6, 5, 4, 3], 5)
      end
      if @timer >= 10 && @timer < 60
        b.hit if b.collide?(self)
      end
      check_hit(section, b)
    else
      area = Rectangle.new(@x + @img_gap.x, @y + @img_gap.y, 160, 160)
      if b.bounds.intersect?(area)
        if b.y > area.y && b.x >= @active_bounds.x - @img_gap.x && b.x + b.w <= @active_bounds.x + @active_bounds.w + @img_gap.x
          @x += 0.1 * (b.x - @x)
          if (b.x - @x).abs <= RANGE
            set_animation(3)
            @attacking = true
            @timer = 0
          end
        elsif b.over?(self)
          hit_by_bomb(section)
        end
        check_hit(section, b)
      else
        super(section)
      end
    end

    if @attacking || @dying
      @hop_timer = 0
    else
      @hop_timer += 1
      @hop_timer = 0 if @hop_timer == 16
    end
  end

  def check_hit(section, bomb)
    unless @invulnerable
      if bomb.explode?(self) or section.explode?(self)
        hit_by_explosion(section)
      else
        proj = section.projectile_hit?(self)
        hit_by_projectile(section) if proj && proj != 8
      end
    end
  end

  def draw(map, section)
    d_y = 16 - 0.25 * (@hop_timer - 8)**2
    @y -= d_y
    super(map)
    @y += d_y
  end
end

class Quartin < Enemy
  class QuartinShield < GameObject
    RADIUS = 36

    attr_reader :dead

    def initialize(x, y, x_c, y_c, angle)
      super(x, y, 24, 24, :sprite_QuartinShield, Vector.new(-4, -4), 2, 2)
      @x_c = x_c
      @y_c = y_c
      @angle = angle
      @timer = 0
    end

    def update(section, x_c, y_c)
      @x_c = x_c
      @y_c = y_c
      if @dying
        animate([1, 2, 3], 5)
        @timer += 1
        @dead = true if @timer == 15
      else
        b = SB.player.bomb
        if b.over?(self)
          b.bounce
          set_animation(1)
          @dying = true
        else
          b.hit if b.collide?(self)
          @angle += 2
          @angle = 0 if @angle == 360
          rad = @angle * Math::PI / 180
          @x = @x_c + Math.cos(rad) * RADIUS - @w / 2
          @y = @y_c + Math.sin(rad) * RADIUS - @h / 2
        end
        if b.explode?(self) || section.explode?(self)
          @dying = true
        else
          proj = section.projectile_hit?(self)
          @dying = true if proj && proj != 8
        end
      end
    end

    def draw(map)
      super(map, 2, 2)
    end
  end

  def initialize(x, y, args, section)
    super(x + 2, y + 2, 28, 28, Vector.new(-4, -4), 2, 2, [0, 1, 2, 1], 10, 360)
    x_c = @x + @w / 2
    y_c = @y + @h / 2
    @shields = [
      QuartinShield.new(@x + 38, @y + 2, x_c, y_c, 0),
      QuartinShield.new(@x + 2, @y - 34, x_c, y_c, 90),
      QuartinShield.new(@x - 34, @y + 2, x_c, y_c, 180),
      QuartinShield.new(@x + 2, @y + 38, x_c, y_c, 270)
    ]
    args = args.split(',')
    @movement = C::TILE_SIZE * args[0].to_i
    @facing_right = args[1].nil?
    @aim = Vector.new(@facing_right ? @x + @movement : @x - @movement, @y)
  end

  def update(section)
    super(section) do
      move_free @aim, 2
      if @speed.x == 0 && @speed.y == 0
        @facing_right = !@facing_right
        @aim = Vector.new(@facing_right ? @x + @movement : @x - @movement, @y)
      end
      @shields.reverse_each do |s|
        s.update(section, @x + @w / 2, @y + @h / 2)
        @shields.delete(s) if s.dead
      end
      hit(section) if @shields.empty? && @hp > 0
    end
  end

  def hit_by_bomb(section)
    SB.player.bomb.hit
  end

  def hit_by_projectile(section); end

  def draw(map, section)
    super(map)
    @shields.each do |s|
      s.draw(map)
    end
  end
end

class Xylophob < FloorEnemy
  def initialize(x, y, args, section)
    super x - 8, y - 22, args, 48, 54, Vector.new(-8, -10), 2, 2, [0, 1, 2, 1], 7, 300, 2, 3
  end

  def get_invulnerable
    super
    @indices = [3]
    set_animation 3
    SB.play_sound(Res.sound(:xylo))
  end

  def return_vulnerable
    super
    @timer = 0
    @indices = [0, 1, 2, 1]
    set_animation 0
    @speed_m += 1
    @speed.x += @speed.x <=> 0
  end
end

class Bardin < FloorEnemy
  def initialize(x, y, args, section)
    super x + 2, y - 28, args, 28, 60, Vector.new(-12, -4), 4, 2, [0, 1, 2, 1], 7, 200, 2, 2
    @timer = 0
  end

  def update(section)
    super(section) do
      @timer += 1
      if @timer == 35
        section.add(Projectile.new(@facing_right ? @x + @w - 4 : @x - 4, @y + 10, 8, @facing_right ? 0 : 180, self))
        @indices = [0, 1, 2, 1]
        @interval = 7
        set_animation(@indices[0])
        set_direction
      end
    end
  end

  def prepare_turn(dir)
    @timer = 0
    @indices = [3, 4, 5, 6, 5, 4, 3]
    @interval = 5
    set_animation @indices[0]
    super(dir)
  end
end

class Dynamike < FloorEnemy
  def initialize(x, y, args, section)
    super x + 2, y - 28, args, 28, 60, Vector.new(-6, -4), 2, 2, [0, 1, 2, 1], 7, 250, 2.5
  end

  def explode(section)
    section.add_effect(Explosion.new(@x + @w / 2, @y + @h / 2, 90, self))
  end

  def hit_by_bomb(section)
    explode(section)
    super(section)
  end

  def hit_by_projectile(section)
    explode(section)
    super(section)
  end

  def hit_by_explosion(section)
    explode(section)
    super(section)
  end
end

class Hooman < Enemy
  def initialize(x, y, args, section)
    super(x + 2, y - 28, 28, 60, Vector.new(-6, -4), 2, 2, [0, 1, 2, 1], 7, 270, 2)
    @facing_right = !args.nil?
    @max_speed.x = 4
  end

  def update(section)
    super(section) do
      forces = Vector.new(0, 0)
      unless @invulnerable
        d = SB.player.bomb.x - @x
        d = 150 if d > 150
        d = -150 if d < -150
        if @bottom && (d < 0 && @left || d > 0 && @right)
          forces.x = d * 0.01666667
          forces.y = -12.5
          @speed.x = 0
        else
          forces.x = d * 0.001
        end
        if d > 0 and not @facing_right
          @facing_right = true
        elsif d < 0 and @facing_right
          @facing_right = false
        end
      end
      move forces, section.get_obstacles(@x, @y), section.ramps
    end
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? :horiz : nil)
  end
end

class Gargoil < Enemy
  RANGE = 320

  def initialize(x, y, args, section)
    super(x - 18, y, 68, 34, Vector.new(-6, -20), 1, 5, [0, 1, 2, 1], 6, 400, 2)
    args = args.split(',')
    @movement = C::TILE_SIZE * args[0].to_i
    @facing_right = args[1].nil?
    @aim = Vector.new(@facing_right ? @x + @movement : @x - @movement, @y)
  end

  def update(section)
    super(section) do
      b = SB.player.bomb
      if @attacking
        move_free(@aim, 7)
        if @speed.x == 0 && @speed.y == 0
          @indices = [0, 1, 2, 1]
          @interval = 3
          set_animation(0)
          @attacking = false
        end
      elsif @aim2
        move_free(@aim2, 2.5)
        if @speed.x == 0 && @speed.y == 0
          @aim2 = nil
          @aim = @prev_aim
          @interval = 6
        end
      elsif b.x > @x && b.x + b.w < @x + @w && b.y > @y && b.y < @y + RANGE
        @prev_aim = @aim
        @aim = Vector.new(b.x + b.w / 2 - @w / 2, b.y + b.h - @h)
        @aim2 = Vector.new(@aim.x, @y)
        @speed.x = @speed.y = 0
        @indices = [3]
        set_animation(3)
        @attacking = true
      else
        move_free(@aim, 3)
        if @speed.x == 0 && @speed.y == 0
          @facing_right = !@facing_right
          @aim = Vector.new(@facing_right ? @x + @movement : @x - @movement, @y)
        end
      end
    end
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? :horiz : nil)
  end
end

class Zirkn < FloorEnemy
  include Boss

  alias :super_update :update

  def initialize(x, y, args, section)
    super(x - 28, y - 84, args, 88, 116, Vector.new(-6, -12), 1, 7, [0, 1, 0, 2], 7, 3000, 4, 5)
    @timer = 0
    @spawn_point = Vector.new(x + C::TILE_SIZE / 2, y + C::TILE_SIZE)
    init
  end

  def update(section)
    b = SB.player.bomb
    update_boss(section, false) do
      if @invulnerable
        super_update(section)
      elsif @state == :attacking
        if b.over?(self)
          b.bounce(false)
        elsif b.collide?(self)
          b.hit
        end
        @timer += 1
        if @hp <= 1
          end_time = 648
          if @timer <= 180 && @timer % 15 == 0
            i = (@timer / 15 - 1) % 12 + 1
            add_fires(section, i, 80)
          elsif @timer > 216 && @timer <= 360 && @timer % 12 == 0
            i = ((@timer - 216) / 12 - 1) % 12 + 1
            add_fires(section, i, 60)
          elsif @timer > 432 && @timer % 9 == 0
            i = ((@timer - 432) / 9 - 1) % 12 + 1
            add_fires(section, i, 45)
          end
        elsif @hp <= 3
          end_time = 360
          if @timer % 15 == 0
            i = (@timer / 15 - 1) % 12 + 1
            add_fires(section, i, 80)
          end
        else
          end_time = 240
          if @timer % 20 == 0
            i = @timer / 20
            add_fires(section, i, 100)
          end
        end
        if @timer == end_time
          set_animation(4)
          section.add_effect(Effect.new(@facing_right ? @x + @w - 136 : @x + 76, @y + 12, :fx_arrow, 3, 1, 8, [0, 1, 2, 1], 150))
          @tail_area = Rectangle.new(@facing_right ? @x + @w - 146 : @x + 66, @y + 76, 80, 40)
          @timer = 0
          @state = :resting
        end
      elsif @state == :resting
        if b.over?(self)
          b.bounce(false)
        elsif b.collide?(self)
          b.hit
        end
        if b.explode?(@tail_area)
          @timer = 0
          @indices = [6]
          set_animation(6)
          hit(section)
        else
          animate([4, 5], 7)
          @timer += 1
          if @timer == (@hp <= 1 ? 180 : 150)
            set_animation(0)
            @timer = 0
            @state = :walking
          end
        end
      else
        super_update(section)
        @timer += 1
        if @timer == 180
          set_animation(3)
          @timer = 0
          @state = :attacking
        end
      end
    end
  end

  def add_fires(section, i, lifetime)
    section.add_effect(Fire.new(@spawn_point.x - i * C::TILE_SIZE, @spawn_point.y, lifetime))
    section.add_effect(Fire.new(@spawn_point.x + i * C::TILE_SIZE, @spawn_point.y, lifetime))
  end

  def hit_by_bomb(section)
    SB.player.bomb.bounce(false)
  end

  def hit_by_projectile(section); end

  def hit_by_explosion(section); end

  def return_vulnerable
    super
    @indices = [0, 1, 0, 2]
    set_animation(0)
    @state = :walking
  end

  def draw(map, section)
    super(map)
    draw_boss
  end
end

class Frock < Enemy
  def initialize(x, y, args, section)
    super x - 10, y - 4, 52, 36, Vector.new(-8, -24), 1, 5, [0, 1], 8, 250

    a = (args || '1').split(',')
    @leaps = 0
    @max_leaps = a[0].to_i
    @facing_right = !a[1].nil?
  end

  def update(section)
    super(section) do
      forces = Vector.new 0, 0
      if @bottom
        @speed.x = 0
        @indices = [0, 1]
        if rand < 0.0333
          @leaps += 1
          if @leaps > @max_leaps
            @leaps = 1
            @facing_right = !@facing_right
          end
          if @facing_right; forces.x = 4.5
          else; forces.x = -4.5; end
          forces.y = -8.5
          set_animation(2)
        end
      else
        animate_once([2, 3], 5)
      end
      prev_g = G.gravity.y
      G.gravity.y *= 0.75
      move(forces, section.get_obstacles(@x, @y), section.ramps)
      G.gravity.y = prev_g
    end
  end

  def hit_by_bomb(section)
    b = SB.player.bomb
    if b.power > 1
      b.bounce
      hit(section)
    else
      b.hit
    end
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? :horiz : nil)
  end
end

class Pantan < Enemy
  def initialize(x, y, args, section)
    super(x, y - 72, 32, 104, Vector.new(-44, -16), 3, 2, [0, 1, 2], 15, 350)
    @leaf1 = Rectangle.new(x - 37, y - 36, 32, 10)
    @leaf2 = Rectangle.new(x + 28, y - 40, 42, 10)
    @roots = Rectangle.new(x - 29, y + 20, 92, 12)
    @bandage1 = Sprite.new(x - 30, y - 36, :fx_bandage)
    @bandage2 = Sprite.new(x + 40, y - 40, :fx_bandage)
  end

  def update(section)
    super(section) do
      b = SB.player.bomb
      if @attacking
        @timer += 1
        if @timer == 30
          @indices = [0, 1, 2]
          @interval = 10
          set_animation(0)
          @attacking = false
        end
      end
      if b.over?(@leaf1)
        b.bounce(!@leaf1_hit)
        @leaf1_hit = true
      elsif b.over?(@leaf2)
        b.bounce(!@leaf2_hit)
        @leaf2_hit = true
      elsif b.bounds.intersect?(@roots)
        b.hit
      end
    end
  end

  def hit_by_bomb(section)
    return if @attacking
    b = SB.player.bomb
    if b.power > 1 || @leaf1_hit && @leaf2_hit
      b.bounce
      hit(section)
    else
      b.hit
      @indices = [3, 4, 4, 4, 4, 3]
      @interval = 5
      set_animation(3)
      @timer = 0
      @attacking = true
    end
  end

  def hit_by_projectile(section); end

  def draw(map, section)
    super(map)
    @bandage1.draw(map, 2, 2) if @leaf1_hit
    @bandage2.draw(map, 2, 2) if @leaf2_hit
  end
end

class Kraklet < SBGameObject
  SCORE = 320

  attr_reader :dying

  def initialize(x, y, args, section)
    super(x - 2, y - 24, 36, 40, :sprite_Kraklet, Vector.new(-12, -56), 3, 2)
    @attack_area = Rectangle.new(@x, @y - 50, @w, @h + 50)
  end

  def update(section)
    if @dying
      @timer += 1
      @dead = true if @timer == 150
      return
    end

    b = SB.player.bomb
    if @attacking
      b.hit if b.bounds.intersect?(@attack_area) && @timer > 15
      @timer += 1
      if @timer <= 20
        animate_once([2, 3, 4], 7)
      elsif @timer == 21
        set_animation(4)
      elsif @timer > 60
        animate_once([4, 3, 2, 0], 7) do
          @attacking = false
        end
      end
    else
      animate([0, 1], 15)
      if b.x + b.w > @x - 20 && @x + @w + 20 > b.x && b.y + b.h > @y - 50 && b.y + b.h <= @y
        set_animation(2)
        @attacking = true
        @timer = 0
      end
    end

    if b.explode?(self) || section.explode?(self) || section.projectile_hit?(self)
      SB.player.stage_score += SCORE
      section.add_score_effect(@x + @w / 2, @y, SCORE)
      set_animation(5)
      @dying = true
      @timer = 0
    end
  end

  def draw(map, section)
    color = 0xffffff
    if SB.stage.stopped && SB.stage.stop_time_duration < 1_000_000_000
      remaining = SB.stage.stop_time_duration - SB.stage.stopped_timer
      color = 0xff6666 if remaining >= 120 || (remaining / 5) % 2 == 0
    end
    super(map, section, 2, 2, 255, color)
  end
end

class Pikey < Enemy
  def initialize(x, y, args, section)
    super(x + 2, y + 1, 28, 28, Vector.new(-5, -5), 3, 2, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 1, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 2, 4], 10, 230)
    @state = @timer = 0
  end

  def update(section)
    super(section)
    @timer += 1
    if @timer == 15
      if @state == 0 || @state == 1
        @y += 1
      else
        @y -= 1
      end
      @state += 1
      @state = 0 if @state == 4
      @timer = 0
    end
  end

  def hit_by_bomb(section)
    SB.player.bomb.hit
  end

  def hit_by_projectile(section); end
end

class Gars < FloorEnemy
  def initialize(x, y, args, section)
    super(x, y - 64, args, 32, 96, Vector.new(-54, -4), 7, 1, [0, 1, 2, 1], 7, 250, 3, 2)
    @dont_fall = true
    @facing_right = !args.nil?
    @forces = Vector.new @speed_m, 0 if @facing_right
  end

  def update(section)
    b = SB.player.bomb
    if @turning && !@dying
      if b.over?(@hit_area)
        if @invulnerable
          b.bounce(false)
        else
          b.bounce
          hit(section, b.power)
        end
      elsif b.bounds.intersect?(@hit_area)
        b.hit
      end
    end
    super(section) do
      @timer += 1
      if @timer == 60
        @indices = [0, 1, 2, 1]
        @interval = 7
        set_animation(0)
        set_direction
      end
    end
  end

  def prepare_turn(dir)
    @hit_area = Rectangle.new(@facing_right ? @x - 6 : @x - 54, @y + 56, 92, 1)
    @timer = 0
    @indices = [3, 4, 5, 5, 5, 5, 5, 5, 5, 5, 4, 3]
    @interval = 5
    set_animation(3)
    super(dir)
  end

  def hit_by_bomb(section)
    SB.player.bomb.bounce(false) unless @turning
  end

  def bounds
    @turning ? Rectangle.new(-1000, -1000, 0, 0) : super
  end
end

class Zingz < Enemy
  MAX_DISTANCE = 10 * C::TILE_SIZE
  SPEED = 2.5
  AIM_WEIGHT = 0.2

  def initialize(x, y, args, section)
    super(x - 9, y + 1, 50, 30, Vector.new(-4, -22), 7, 1, [0, 1, 2, 1, 3, 4, 5, 4], 5, 80)
    section.add_interacting_element(self)
  end

  def update(section)
    super(section) do
      b = SB.player.bomb
      new_aim = Vector.new(b.x + b.w / 2 - @w / 2, b.y + b.h / 2 - @h / 2)
      distance = new_aim.distance(Vector.new(@x, @y))
      next unless distance <= MAX_DISTANCE
      if @aim
        @aim = new_aim * AIM_WEIGHT + @aim * (1 - AIM_WEIGHT)
      else
        @aim = new_aim
      end
      move_free(@aim, SPEED)
    end

    if @dying && !@removed
      section.remove_interacting_element(self)
      @removed = true
    end
  end
end

class Globb < FloorEnemy
  include Boss

  alias :super_update :update

  def initialize(x, y, args, section)
    super(x - 26, y - 82, args, 84, 114, Vector.new(-28, -8), 2, 3, [0, 1, 2, 1], 10, 3700, 2.5, 5)
    @start_pos = Vector.new(x, y)
    @floor_tolerance = 16
    @turn_counter = 0
    @timer = 0
    @boxes = []
    replace_spawns(Box, [[-11, 0], [-9, -3]], section)
    @spikes = []
    replace_spawns(FixedSpikes, [[-15, 1], [-14, 1], [-13, 1]], section)
    init
  end

  def replace_spawns(type, positions, section)
    list = type == Box ? @boxes : @spikes
    list.each { |obj| obj.instance_exec { remove_obstacle(section); @dead = true } }
    list.clear
    positions.each do |p|
      list << type.new(@start_pos.x + p[0] * C::TILE_SIZE, @start_pos.y + p[1] * C::TILE_SIZE, type == Box ? list.size : '0,2', section)
    end
    list.each { |obj| section.add(obj) }
  end

  def update(section)
    update_boss(section, false) do
      if @invulnerable
        move(Vector.new(0, 0), section.get_obstacles(@x, @y, @w, @h), [])
        @control_timer += 1
        if @control_timer > 0 && @bottom
          @speed.x = 0
        end
        if @control_timer == 120
          set_animation(0)
          @invulnerable = false
          @speed.x = @facing_right ? @speed_m : -@speed_m

          if @hp == 3
            replace_spawns(Box, [[9, -6], [10, -3]], section)
            replace_spawns(FixedSpikes, [[13, 1], [14, 1], [15, 1]], section)
          elsif @hp == 1
            replace_spawns(Box, [[-9, -3], [9, -6], [11, -6], [10, -3]], section)
            replace_spawns(FixedSpikes, [[-15, 1], [-14, 1], [-13, 1]], section)
          end
          @boxes.each { |b| b.activate(section) }
        end
      elsif @bottom.is_a?(SpecialBlock) && @bottom.info == :fixedSpikes
        hit(section)
        set_animation(5)
        @stored_forces = Vector.new(@x < @start_pos.x ? 10 : -10, -35)
        @control_timer = 0
      else
        super_update(section) do
          if @turn_counter % 3 == 0
            if @timer % 15 == 0
              section.add(PoisonGas.new(@start_pos.x + @w / 2 + (@timer / 5 + @turn_counter / 3 - 7) * 64 + 16, @y + 64, @hp < 2 ? 900 : @hp < 4 ? 840 : 600, section))
              if @hp < 4
                section.add(PoisonGas.new(@start_pos.x + @w / 2 + (@timer / 5 + @turn_counter / 3 - 7) * 64 + 16, @y - 12, @hp < 2 ? 900 : 840, section))
              end
            end
            @timer += 1
            if @timer == 60
              @indices = [0, 1, 2, 1]
              @interval = 10
              set_animation(0)
              set_direction
              @timer = 0
              @turn_counter = 0 if @turn_counter == 9
            end
          else
            set_direction
          end
        end
      end
    end
  end

  def prepare_turn(dir)
    super(dir)
    @turn_counter += 1
    if @turn_counter % 3 == 0
      @indices = [3, 4]
      @interval = 7
      set_animation(3)
    end
  end

  def hit_by_bomb(section)
    SB.player.bomb.bounce(false)
  end

  def hit_by_projectile(section); end
  def hit_by_explosion(section); end

  def draw(map, section)
    super(map)
    draw_boss
  end
end

class Bombark < FloorEnemy
  EXPLOSION_RADIUS = 90

  def initialize(x, y, args, section)
    super(x + 6, y + 6, args, 20, 26, Vector.new(-8, -6), 3, 2, [1, 2, 1, 0], 7, 360, 3, 2)
  end

  def update(section)
    if @invulnerable || @dying
      super(section)
      return
    end

    if @exploding
      animate([4, 5], 7)
      @timer += 1
      if @timer == 80
        set_animation 1
        @exploding = false
        @timer = 0
      end
    elsif @alert
      check_hit(section)

      @timer += 1
      if @timer == 30
        section.add_effect(Explosion.new(@x + @w / 2, @y + @h / 2, EXPLOSION_RADIUS, self))
        set_animation 4
        @exploding = true
        @alert = false
        @timer = 0
      end
    else
      super(section)

      b = SB.player.bomb
      d_x = @x + @w / 2 - b.x - b.w / 2
      d_y = @y + @h / 2 - b.y - b.h / 2
      if d_x * d_x + d_y * d_y <= EXPLOSION_RADIUS * EXPLOSION_RADIUS
        section.add_effect(Effect.new(@x + @w / 2 - 4, @y - 30, :fx_alert, nil, nil, 0, nil, 30))
        set_animation 3
        @alert = true
        @timer = 0
      end
    end
  end

  def check_hit(section)
    unless SB.player.dead?
      b = SB.player.bomb
      if b.over?(self)
        hit_by_bomb(section)
      else
        if b.collide?(self)
          b.hit
        end
        if b.explode?(self) or section.explode?(self)
          hit_by_explosion(section)
        else
          proj = section.projectile_hit?(self)
          hit_by_projectile(section) if proj && proj != 8
        end
      end
    end
  end
end

class Vamdark < Enemy
  RANGE_H = 80
  RANGE_H_EXT = 120
  RANGE_V = 270

  def initialize(x, y, args, section)
    super(x + 4, y - 4, 24, 66, Vector.new(-48, 0), 2, 4, [0], 7, 250, 2)
    @start_pos = Vector.new(@x, @y)
    @state = :waiting
    @angle = 0
  end

  def update(section)
    super(section) do
      b = SB.player.bomb
      if @state == :going_down
        move_free(@aim, 5)
        @angle += 6 if @angle < 180
        @timer += 1
        if @speed.x == 0 && @speed.y == 0
          @indices = [4, 5, 6, 5]
          set_animation(4)
          @attack_area = Rectangle.new(@x - 46, @y + 20, 116, 36)
          @state = :attacking
          @timer = 0
        end
      elsif @state == :attacking
        b.hit if b.bounds.intersect?(@attack_area)
        @angle += 6 if @angle < 180
        @timer += 1
        if @timer == 90
          @indices = [3, 3, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          set_animation(3)
          @state = :returning
          @timer = 0
        end
      elsif @state == :returning
        move_free(@start_pos, 5)
        @angle += 6 if @angle < 360
        @timer += 1
        if @speed.x == 0 && @speed.y == 0
          @indices = [0]
          set_animation(0)
          @angle = 0
          @state = :waiting
        end
      elsif b.y > @y && b.y < @y + RANGE_V
        if b.x + b.w >= @x - RANGE_H && b.x < @x + @w + RANGE_H
          @aim = Vector.new(b.x + b.w / 2 + 30 * b.speed.x - @w / 2, b.y + b.h / 2 - @h + 20)
          @indices = [2, 3, 4, 5, 6, 5, 4, 5, 6, 5, 4, 5, 6, 5, 4, 5, 6]
          set_animation(2)
          @state = :going_down
          @timer = 0
        elsif b.x + b.w >= @x - RANGE_H_EXT && b.x < @x + @w + RANGE_H_EXT
          @indices = [1]
          set_animation(1)
        else
          @indices = [0]
          set_animation(0)
        end
      end
    end
  end

  def draw(map, section)
    super(map, section, 2, 2, 0xff, 0xffffff, @angle)
  end
end

class Luminark < Enemy
  LIGHT_TILES = [
    [0, 0, 0],
    [-1, 0, 40], [0, -1, 40], [1, 0, 40], [0, 1, 40],
    [-1, -1, 80], [1, -1, 80], [-1, 1, 80], [1, 1, 80],
    [-2, 0, 120], [0, -2, 120], [2, 0, 120], [0, 2, 120],
    [-1, -2, 150], [1, -2, 150], [2, -1, 150], [2, 1, 150], [1, 2, 150], [-1, 2, 150], [-2, 1, 150], [-2, -1, 150],
  ]

  def initialize(x, y, args, section)
    super(x - 10, y - 18, 52, 46, Vector.new(-4, -10), 4, 2, [0, 1, 2, 3, 4, 5], 7, 300, 2)
    @leaps = 1000
    @max_leaps = args.to_i
    @facing_right = true
    @idle_timer = 0
  end

  def update(section)
    super(section) do
      next if @invulnerable
      forces = Vector.new 0, 0
      if @bottom
        @speed.x = 0
        @idle_timer += 1
        if @idle_timer > 60
          @leaps += 1
          if @leaps > @max_leaps
            @leaps = 1
            @facing_right = !@facing_right
          end
          if @facing_right; forces.x = 3
          else; forces.x = -3; end
          forces.y = -6
          @idle_timer = 0
        end
      end
      prev_g = G.gravity.y
      G.gravity.y *= 0.5
      move(forces, section.get_obstacles(@x, @y), section.ramps)
      G.gravity.y = prev_g
    end
  end

  def hit_by_bomb(section)
    SB.player.bomb.hit
  end

  def hit_by_explosion(section); end

  def draw(map, section)
    super(map)
    section.add_light_tiles(LIGHT_TILES, @x, @y, @w, @h)
  end
end

class Drepz < Enemy
  LIGHT_TILES = [
    [0, 0, 0],
    [-1, 0, 25], [0, -1, 25], [1, 0, 25], [0, 1, 25],
    [-1, -1, 50], [1, -1, 50], [-1, 1, 50], [1, 1, 50],
    [-2, 0, 75], [0, -2, 75], [2, 0, 75], [0, 2, 75],
    [-1, -2, 100], [1, -2, 100], [2, -1, 100], [2, 1, 100], [1, 2, 100], [-1, 2, 100], [-2, 1, 100], [-2, -1, 100],
    [-3, 0, 125], [0, -3, 125], [3, 0, 125], [0, 3, 125],
    [-3, -1, 150], [-2, -2, 150], [-1, -3, 150], [1, -3, 150], [2, -2, 150], [3, -1, 150],
    [3, 1, 150], [2, 2, 150], [1, 3, 150], [-1, 3, 150], [-2, 2, 150], [-3, 1, 150],
    [0, -4, 175], [2, -3, 175], [3, -2, 175], [4, 0, 175], [3, 2, 175], [2, 3, 175],
    [0, 4, 175], [-2, 3, 175], [-3, 2, 175], [-4, 0, 175], [-3, -2, 175], [-2, -3, 175]
  ]

  include Boss

  alias :super_update :update

  def initialize(x, y, args, section)
    super(x - 5, y - 44, 42, 76, Vector.new(-10, -20), 3, 2, [1, 2, 1, 0], 7, 7000, 7)
    @img_index = 1
    @timer = 0
    @jump_points = args.split(':').map { |p| p.split(',').map { |c| c.to_i * C::TILE_SIZE } }
    @point_index = 0
    @attack_area_limits = [x - 13 * C::TILE_SIZE, x + 14 * C::TILE_SIZE - 1]
    @max_speed = Vector.new(100, 100)
    init
  end

  def update(section)
    update_boss(section) do
      forces = Vector.new(0, 0)
      obstacles = section.get_obstacles(@x, @y, @w, @h)
      set_speed = false
      if @state == :acting
        @timer += 1
        if @left || @speed.x < 0 && !section.obstacle_at?(@x - 1, @y + @h)
          forces.x = @hp <= 1 ? 6 : @hp <= 4 ? 5 : 4.5
          set_speed = true
          @facing_right = true
        elsif @speed.x == 0 || @right || @speed.x > 0 && !section.obstacle_at?(@x + @w, @y + @h)
          forces.x = -(@hp <= 1 ? 6 : @hp <= 4 ? 5 : 4.5)
          set_speed = true
          @facing_right = false
        end
        if @timer >= (300 - (7 - @hp) * 15)
          d_x = @jump_points[@point_index][0] - 5 - @x
          d_y = @jump_points[@point_index][1] - 44 - @y
          v_y = -Math.sqrt(-2 * G.gravity.y * (d_y - C::TILE_SIZE))
          v_x = d_x / ((-v_y / G.gravity.y) + Math.sqrt(2 * C::TILE_SIZE / G.gravity.y))
          forces.x = v_x
          forces.y = v_y
          set_speed = true
          @point_index += 1
          @point_index = 0 if @point_index == @jump_points.size
          @timer = 0
          @indices = [3]
          @state = :jumping
        end
      elsif @state == :jumping
        if @bottom
          @speed.x = 0
          @indices = [1]
          @timer += 1
          if @timer == 60
            @indices = [4, 5]
            @timer = 0
            @state = :attacking
          end
        end
      elsif @state == :attacking
        @timer += 1
        if @timer % 30 == 0
          pos = SB.player.bomb.x - 4 * C::TILE_SIZE + rand(9 * C::TILE_SIZE)
          pos = @attack_area_limits[0] if pos < @attack_area_limits[0]
          pos = @attack_area_limits[1] if pos > @attack_area_limits[1]
          section.add(Lightning.new(pos, 0, nil, section))
        end
        if @timer == (@hp <= 1 ? 300 : @hp <= 4 ? 240 : 180)
          forces.y = -5
          @indices = [3]
          @state = :returning
        end
      elsif @state == :returning
        obstacles = obstacles.select { |o| !o.passable }
        if @bottom
          @indices = [1, 2, 1, 0]
          @timer = 0
          @state = :acting
        end
      end
      move(forces, obstacles, section.ramps, set_speed)
    end
  end

  def hit_by_explosion(section)
    hit(section)
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? :horiz : nil)
    section.add_light_tiles(LIGHT_TILES, @x, @y, @w, @h)
    draw_boss
  end
end

class Bombinfant < Enemy
  MIN_IDLE_TIME = 30
  IDLE_TIME_VAR = 90
  MIN_WALK_TIME = 90
  WALK_TIME_VAR = 90
  SPEED = 3

  def initialize(x, y, args, section)
    super(x + 2, y - 4, 28, 36, Vector.new(-26, -16), 1, 5, [1, 3], 15, 320, 2)
    @img_index = 1
    @idle = true
    @timer = 0
    @time_limit = MIN_IDLE_TIME + rand(IDLE_TIME_VAR)
    @dont_fall = args.nil?
  end

  def update(section)
    super(section) do
      attack_area = Rectangle.new(@facing_right ? @x + @w + 6 : @x - 22, @y - 10, 16, 40)
      b = SB.player.bomb
      if b.bounds.intersect?(attack_area)
        b.hit
      end

      forces = Vector.new(0, 0)

      if @idle
        @timer += 1
        if @timer == @time_limit
          forces.x = @facing_right ? SPEED : -SPEED
          @indices = [0, 1, 2, 1]
          @interval = 8
          set_animation(0)
          @time_limit = MIN_WALK_TIME + rand(WALK_TIME_VAR)
          @timer = 0
          @idle = false
        end
      else
        if @facing_right && (@right || @dont_fall && !section.obstacle_at?(@x + @w, @y + @h))
          @speed.x = 0
          forces.x = -SPEED
          @facing_right = false
        elsif !@facing_right && (@left || @dont_fall && !section.obstacle_at?(@x - 1, @y + @h))
          @speed.x = 0
          forces.x = SPEED
          @facing_right = true
        end

        @timer += 1
        if @timer == @time_limit
          forces.x = @speed.x = 0
          @indices = [1, 3]
          @interval = 15
          set_animation(1)
          @time_limit = MIN_IDLE_TIME + rand(IDLE_TIME_VAR)
          @timer = 0
          @idle = true
        end
      end

      move(forces, section.get_obstacles(@x, @y), section.ramps)
    end
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? :horiz : nil)
  end
end

class Bombarcher < Enemy
  def initialize(x, y, args, section)
    super(x + 2, y - 4, 28, 36, Vector.new(-26, -24), 3, 2, [0, 1], 15, 200)
    @shoot_interval = (args || 60).to_i
    @timer = 0
    @active_bounds.h += 3 * C::TILE_SIZE
  end

  def update(section)
    super(section) do
      c = @x + @w / 2
      b = SB.player.bomb
      b_c = b.x + b.w / 2
      if b_c >= c && !@facing_right
        @facing_right = true
      elsif b_c < c && @facing_right
        @facing_right = false
      end

      @timer += 1
      if @attacking
        if @timer == 20
          section.add(Projectile.new(@facing_right ? @x + @w : @x - 8, @y + 4, 12, @facing_right ? 330 : 210, self))
        elsif @timer == 30
          @indices = [0, 1]
          @interval = 15
          set_animation(0)
          @attacking = false
          @timer = 0
        end
      elsif @timer == @shoot_interval
        @indices = [2, 3, 4]
        @interval = 10
        set_animation(2)
        @attacking = true
        @timer = 0
      end
    end
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? :horiz : nil)
  end
end

class Bombnight < Enemy
  SPEED = 4.5

  def initialize(x, y, args, section)
    super(x, y - 18, 60, 50, Vector.new(-38, -34), 2, 3, [0, 1, 2, 3, 4, 5], 5, 480, 3)
    @stored_forces.x = -SPEED
  end

  def update(section)
    super(section) do
      knight_area = Rectangle.new(@facing_right ? @x + 14 : @x + 18, @y - 24, 28, 28)
      b = SB.player.bomb
      if b.over?(knight_area)
        hit_by_bomb(section)
      elsif b.bounds.intersect?(knight_area)
        b.hit
      end
      if section.projectile_hit?(knight_area) && !@invulnerable
        hit(section)
      end

      forces = Vector.new(0, 0)
      if @facing_right && (@right || !section.obstacle_at?(@x + @w, @y + @h))
        @speed.x = 0
        forces.x = -SPEED
        @facing_right = false
      elsif !@facing_right && (@left || !section.obstacle_at?(@x - 1, @y + @h))
        @speed.x = 0
        forces.x = SPEED
        @facing_right = true
      end
      move(forces, section.get_obstacles(@x, @y, @w, @h), section.ramps)
    end
  end
  
  def hit_by_projectile(section); end

  def hit_by_explosion(section)
    hit(section, 2)
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? :horiz : nil)
  end
end

class Bombaladin < Enemy
  FORCE = 0.1

  def initialize(x, y, args, section)
    super(x, y - 18, 60, 50, Vector.new(-38, -48), 2, 3, [0, 1, 2, 3, 4, 5], 5, 750, 3)
    @max_speed.x = 4.5
  end

  def update(section)
    super(section) do
      knight_area = Rectangle.new(@facing_right ? @x + 8 : @x + 12, @y - 24, 40, 28)
      b = SB.player.bomb
      if b.over?(knight_area)
        hit_by_bomb(section)
      elsif b.bounds.intersect?(knight_area)
        b.hit
      end
      if section.projectile_hit?(knight_area) && !@invulnerable
        hit(section)
      end

      attack_area = Rectangle.new(@facing_right ? @x + 50 : @x - 6, @y - 46, 16, 30)
      if b.bounds.intersect?(attack_area)
        b.hit
      end

      forces = Vector.new(0, 0)
      if @invulnerable
        @speed.x = 0
      else
        d = b.x + b.w / 2 - @x - @w / 2
        forces.x = (d <=> 0) * FORCE * (@bottom.is_a?(Ramp) ? 2 : 1)
      end
      move(forces, section.get_obstacles(@x, @y, @w, @h), section.ramps)
      if @speed.x > 0 && !@facing_right
        @facing_right = true
      elsif @speed.x < 0 and @facing_right
        @facing_right = false
      end
    end
  end

  def hit_by_projectile(section); end

  def hit_by_explosion(section)
    hit(section, 2)
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? :horiz : nil)
  end
end

class Bomblancer < Enemy
  SPEED = 3
  RANGE = 40

  def initialize(x, y, args, section)
    super(x + 2, y - 4, 28, 36, Vector.new(-58, -44), 2, 3, [0, 1, 2, 1], 7, 300, 2)
    @stored_forces.x = -SPEED
  end

  def update(section)
    super(section) do
      return if @invulnerable

      b = SB.player.bomb
      if @attack == :up
        attack_area = Rectangle.new(@facing_right ? @x + 26 : @x - 12, @y - 44, 14, 80)
        b.hit if b.bounds.intersect?(attack_area)
        @timer += 1
        finish_attack if @timer == 120
      elsif @attack == :side
        @timer += 1
        if @timer >= 30
          attack_area = Rectangle.new(@facing_right ? @x + 28 : @x - 60, @y + 14, 60, 14)
          b.hit if b.bounds.intersect?(attack_area)
        end
        if @timer == 30
          @indices = [4]
          set_animation(4)
        elsif @timer == 90
          finish_attack
        end
      elsif b.y + b.h > @y && @y + @h > b.y &&
            (@facing_right && b.x > @x && b.x < @x + @w + RANGE ||
             !@facing_right && b.x < @x && b.x + b.w > @x - RANGE)
        @attack = :side
        @timer = 0
        @indices = [1]
        set_animation(1)
        section.add_effect(Effect.new(@x + @w / 2 - 4, @y - 30, :fx_alert, nil, nil, 0, nil, 30))
      elsif b.x + b.w > @x && @x + @w > b.x &&
            b.y < @y && b.y + b.h > @y - RANGE
        @attack = :up
        @indices = [3]
        set_animation(3)
        @timer = 0
      else
        forces = Vector.new(0, 0)
        if @facing_right && (@right || !section.obstacle_at?(@x + @w, @y + @h))
          @speed.x = 0
          forces.x = -SPEED
          @facing_right = false
        elsif !@facing_right && (@left || !section.obstacle_at?(@x - 1, @y + @h))
          @speed.x = 0
          forces.x = SPEED
          @facing_right = true
        end
        move(forces, section.get_obstacles(@x, @y, @w, @h), section.ramps)
      end
    end
  end

  def finish_attack
    @indices = [0, 1, 2, 1]
    set_animation(0)
    @attack = nil
  end

  def hit_by_bomb(section)
    is_hit = @attack == :side && !@invulnerable
    if is_hit
      finish_attack
      hit(section)
    end
    SB.player.bomb.bounce(is_hit)
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? :horiz : nil)
  end
end

class Gaxlon < Enemy
  V_MARGIN = (2 * C::TILE_SIZE).to_f

  include Boss

  alias :super_update :update

  def initialize(x, y, args, section)
    super(x - 14, y - 86, 60, 118, Vector.new(-26, -42), 3, 2, [0, 1], 10, 10000, 10)
    @max_speed = Vector.new(100, 100)
    args = args.split('%')
    @jump_points = args[0].split('$').map { |a| a.split(':').map { |p| p.split(',').map { |c| c.to_i * C::TILE_SIZE } } }
    @spawn_points = args[1].split('$').map { |a| a.split(':').map { |p| p.split(',').map { |c| c.to_i * C::TILE_SIZE } } }
    @point_index = 0
    @subpoint_index = 0
    @timer = 0
    @spawns = {}
    @rect = Rectangle.new(@spawn_points[5][0][0], @spawn_points[5][0][1], C::TILE_SIZE, C::TILE_SIZE)
    init(:finalBoss)
  end

  def update(section)
    update_boss(section, false) do
      forces = Vector.new(0, 0)
      obstacles = section.get_obstacles(@x, @y, @w, @h)

      if @invulnerable
        super_update(section)
        move(forces, obstacles, section.ramps)
        return
      end

      b = SB.player.bomb
      unless SB.player.dead?
        if b.over?(self)
          hit_by_bomb(section)
        else
          if b.collide?(self)
            b.hit
          end
          if b.explode?(self, nil, @y + @h) || section.projectile_hit?(self)
            hit(section)
          end
        end
      end

      set_speed = false
      if @state == :will_jump
        @timer += 1
        if @timer == 30
          forces = jump_to(@jump_points[0][@point_index])
          set_speed = true
          @point_index += 1
          @timer = 0
        end
      elsif @state == :jumping
        if @bottom
          @speed.x = 0
          @indices = [0, 1]
          set_animation(0)
          @state = :acting
        end
      elsif @hp >= 9
        @timer += 1
        if @timer % 60 == 0 && @timer <= 120
          forces = jump_to(@jump_points[1][@subpoint_index])
          set_speed = true
          @subpoint_index = (@subpoint_index + 1) % @jump_points[1].size
        end
        if @timer == 150
          @indices = [3, 4]
          set_animation(3)
          times = @hp > 9 ? 1 : 2
          times.times do
            @spawn_points[0].each_with_index do |p, i|
              x = p[0] - 64 + rand(128)
              y = p[1] - 64 + rand(128)
              section.add(Projectile.new(x, y, 13, i * 90, self))
            end
          end
          if @spawns.size < @spawn_points[1].size
            index = (0...@spawn_points[1].size).find { |i| @spawns[i].nil? }
            x = @spawn_points[1][index][0]
            y = @spawn_points[1][index][1]
            item = Attack5.new(x, y, nil, section, {})
            add_spawn_effect(section, x, y)
            section.add(item)
            SB.stage.add_switch(item)
            @spawns[index] = item
          end
        elsif @timer == 210
          @indices = [0, 1]
          set_animation(0)
          @timer = 30
        end
      elsif @hp >= 7
        if @timer == 0
          @spawns.each do |_, v|
            add_spawn_effect(section, v.x, v.y)
            v.instance_exec { @dead = true }
          end
          points = @subpoint_index == 0 ? @spawn_points[2][0..2] : @spawn_points[2][3..5]
          points.each_with_index do |p, i|
            item = Heart.new(p[0], p[1], nil, section)
            add_spawn_effect(section, p[0], p[1])
            section.add(item)
            @spawns[i] = item
          end
          @subpoint_index = @subpoint_index == 0 ? 1 : 0
        end
        @timer += 1
        if @timer == 300
          forces = jump_to(@jump_points[2][@subpoint_index])
          set_speed = true
          @timer = 0
        end
      elsif @hp >= 5
        @timer += 1
        if @timer == 60
          forces = jump_to(@jump_points[3][@subpoint_index])
          set_speed = true
          @subpoint_index = (@subpoint_index + 1) % @jump_points[3].size
        elsif @timer == 90
          @indices = [3, 4]
          set_animation(3)
          @spawn_points[3].each_with_index do |p, i|
            x = p[0] - 96 + rand(192)
            y = p[1] - 96 + rand(192)
            section.add(Projectile.new(x, y, 13, (i / 2) * 90, self))
          end
        elsif @timer == 150
          @indices = [0, 1]
          set_animation(0)
        elsif @timer == 330
          @timer = 0
        end
      elsif @hp >= 3
        @timer += 1
        if @timer % 60 == 0
          forces = jump_to(@jump_points[4][@subpoint_index])
          set_speed = true
          @subpoint_index = (@subpoint_index + 1) % @jump_points[4].size
        end
        if @timer == 180
          if @spawns.empty?
            index = rand(@spawn_points[4].size)
            x = @spawn_points[4][index][0]
            y = @spawn_points[4][index][1]
            item = GunPowder.new(x, y, '3', section, nil)
            add_spawn_effect(section, x, y)
            section.add(item)
            @spawns[index] = item
            @timer = 0
          else
            @timer -= 60
          end
        end
      else
        should_spawn = false
        if @hp == 1 && @subpoint_index == 0
          forces = jump_to(@jump_points[5][0])
          set_speed = true
          should_spawn = true
          @subpoint_index = 1
        end
        if @spawns.empty? && (should_spawn || @rect.intersect?(b.bounds))
          x = @spawn_points[5][1][0]
          y = @spawn_points[5][1][1]
          item = Hourglass.new(x, y, nil, section)
          add_spawn_effect(section, x, y)
          section.add(item)
          @spawns[0] = item
        end
      end

      @spawns.keys.reverse_each do |k|
        if @spawns[k].dead?
          obj = @spawns.delete(k)
          SB.stage.delete_switch(obj)
        end
      end

      animate(@indices, @interval)
      move(forces, obstacles, section.ramps, set_speed)
      set_active_bounds(section)
      @facing_right = @speed.x > 0
    end
  end

  def jump_to(point)
    d_x = point[0] - 14 - @x
    d_y = point[1] - 86 - @y
    d_y_1 = d_y > 0 ? -V_MARGIN : d_y - V_MARGIN
    d_y_2 = d_y > 0 ? d_y + V_MARGIN : V_MARGIN
    v_y = -Math.sqrt(-2 * G.gravity.y * d_y_1)
    v_x = d_x / ((-v_y / G.gravity.y) + Math.sqrt(2 * d_y_2 / G.gravity.y))
    @indices = [2]
    set_animation(2)
    @state = :jumping
    Vector.new(v_x, v_y)
  end

  def add_spawn_effect(section, x, y)
    section.add_effect(Effect.new(x - 16, y - 16, :fx_spawn, 2, 2, 6))
  end

  def get_invulnerable
    super
    @speed.x = 0
    @indices = [@img.size - 1]
    set_animation(@img.size - 1)
  end

  def return_vulnerable
    super
    @indices = [0, 1]
    set_animation(0)
    if @hp % 2 == 0
      @subpoint_index = 0
      @timer = 0
      @spawns.clear
      @state = :will_jump
    end
  end

  def hit_by_bomb(section)
    return if @invulnerable
    super(section)
    return if @hp <= 0
    b = SB.player.bomb
    entrance = @hp >= 8 ? 21 : @hp >= 6 ? 22 : @hp >= 4 ? 23 : 25
    section.add(Vortex.new(b.x + b.w / 2 - 27, b.y + b.h / 2 - 27, "#{entrance},$", section))
  end

  def hit(section, amount = 1)
    super(section, amount)
    section.activate_object(MovingWall, @hp == 8 ? 4 : @hp == 6 ? 5 : @hp == 4 ? 6 : 7) if @hp % 2 == 0
  end

  def draw(map, section)
    super(map, section, 2, 2, 255, 0xffffff, nil, @facing_right ? :horiz : nil)
    draw_boss
  end
end