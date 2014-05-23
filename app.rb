require 'sinatra'
require 'mysql'
require 'json'

enable :sessions
set :bind, '0.0.0.0'

#get '/user/find' do
#  if params[:token].nil? then
#    status 403
#    body ''
#  else
#    if params[:email].nil? then
#      status 404
#      body ''
#    else
#      mysql = Mysql.new 'localhost', 'root', 'pass'
#      rs = mysql.query \
#        "SELECT `id` FROM `ibetyou`.`user` WHERE `token`='#{params[:token]}'"
#      if rs.num_rows === 0
#        mysql.close
#        status 404
#        body ''
#      else
#        rs = mysql.query \
#          "SELECT `id` FROM `ibetyou`.`user` WHERE `email`='#{params[:email]}"
#        if rs.num_rows === 0
#          mysql.close
#          status 404
#          body ''
#        else
#          mysql.close
#          body {'result' => rs.fetch_row['asdf']}
#          status 200
#        end
#      end
#    end
#  end
#end

get '/dashboard' do
  mysql = Mysql.new 'localhost', 'root', 'pass'
  mysql.query 'use ibetyou'
  if params[:token].nil?
    status 403
    body ''
  else
    rs = mysql.query \
      "SELECT * FROM `ibetyou`.`user` WHERE `token`='#{params[:token]}'"
    if rs.num_rows === 0
      mysql.close
      status 403
      body ''
    else
      user = rs.fetch_hash
      users_won = Hash.new(0)
      users_lost = Hash.new(0)
      rs2 = mysql.query \
        "SELECT `email`,count(1) as c FROM `user` INNER JOIN " \
        " `bet` ON `user`.`id` = `bet`.`challenger` WHERE `bet`.`status`='won' " \
        " GROUP BY `challenger`  ORDER BY `c` DESC"

      # Won by challenger
      rs2.each_hash do |r|
        users_won[r['email']] = users_won[r['email']] + r['c'].to_i
      end

      # Lost by challenger
      rs3 = mysql.query \
        "SELECT `email`,count(1) as c FROM `user` INNER JOIN " \
        " `bet` ON `user`.`id` = `bet`.`challenger` WHERE `bet`.`status`='lost' " \
        " GROUP BY `challenger`  ORDER BY `c` DESC"
      rs3.each_hash do |r|
        users_lost[r['email']] = users_lost[r['email']] + r['c'].to_i
      end

      # Won by challengee
      rs4 = mysql.query \
        "SELECT `email`,count(1) as c FROM `user` INNER JOIN " \
        " `bet` ON `user`.`id` = `bet`.`challengee` WHERE `bet`.`status`='lost' " \
        " GROUP BY `challengee` ORDER BY `c` DESC"
      rs4.each_hash do |r|
        users_won[r['email']] = users_won[r['email']] + r['c'].to_i
      end

      # Lost by challengee
      rs5 = mysql.query \
        "SELECT `email`,count(1) as c FROM `user` INNER JOIN " \
        " `bet` ON `user`.`id` = `bet`.`challengee` WHERE `bet`.`status`='won' " \
        " GROUP BY `challengee` ORDER BY `c` DESC"
      rs5.each_hash do |r|
        users_lost[r['email']] = users_lost[r['email']] + r['c'].to_i
      end
      users = []
      users_won.each_pair do |k,v|
        users << {'email' => k, 'won' => v}
      end
      users_lost.each_pair do |k,v|
        users << {'email' => k, 'lost' => v}
      end
      puts "total: #{users}"
      result = {
        'result' => {
          'points' => user['points'],
          'users' => users
        }
      }
      status 200
      body result.to_json
      mysql.close
    end
  end
end

get '/bet/mine' do
  mysql = Mysql.new 'localhost', 'root', 'pass'
  if params[:token].nil?
    status 403
    body ''
  else
    rs = mysql.query \
      "SELECT * FROM `ibetyou`.`user` WHERE `token`='#{params[:token]}'"
    if rs.num_rows === 0
      mysql.close
      status 403
      body ''
    else
      user = rs.fetch_hash
      rs = mysql.query \
        "SELECT * FROM `ibetyou`.`bet` WHERE `challenger`=#{user['id']} OR `challengee`=#{user['id']}"
      bets = []
      rs.each_hash do |bet|
        rs2 = mysql.query "SELECT `email` FROM `ibetyou`.`user` WHERE `id`=#{bet['challengee']}"
        rs3 = mysql.query "SELECT `email` FROM `ibetyou`.`user` WHERE `id`=#{bet['challenger']}"
        challenger = rs2.fetch_hash
        challengee = rs3.fetch_hash
        bets << {
          'id' => bet['id'],
          'challenger' => challenger['email'],
          'challengee' => challengee['email'],
          'description' => bet['description'],
          'points' => bet['points'],
          'status' => bet['status']
        }
      end
      mysql.close
      status 200
      result = {'result' => bets}
      body result.to_json
    end
  end
end

post '/bet/new' do
  mysql = Mysql.new 'localhost', 'root', 'pass'
  if params[:token].nil?
    status 403
    body ''
  else
    if params[:challengee].nil? || params[:description].nil? || params[:points].nil?
      mysql.close
      status 400
      result = {"error" => "required_arguments: challengee, description, points"}
      body result.to_json
    else
      rs = mysql.query \
        "SELECT * FROM `ibetyou`.`user` WHERE `token`='#{params[:token]}'"
      if rs.num_rows === 0
        mysql.close
        status 403
        body ''
      else
        challenger = rs.fetch_hash
        rs = mysql.query \
          "SELECT * FROM `ibetyou`.`user` WHERE `email`='#{params[:challengee]}'"
        if rs.num_rows === 0
          mysql.close
          status 400
          result = {"error" => "invalid challengee"}
          body result.to_json
        else
          challengee = rs.fetch_hash
          if challenger['points'].to_i < params[:points].to_i
            mysql.close
            status 400
            result = {"error" => "challenger without enough points"}
            body result.to_json
          elsif challengee['points'].to_i < params[:points].to_i
            mysql.close
            status 400
            result = {"error" => "challengee without enough points"}
            body result.to_json
          elsif challengee['email'] == challenger['email']
            mysql.close
            status 400
            result = {"error" => "cant bet against yourself dude!"}
            body result.to_json            
          else
            mysql.query \
              "UPDATE `ibetyou`.`user` SET `points`=`points`-#{params[:points]} " \
              " WHERE `id`=#{challenger['id']}"
            mysql.query \
              "INSERT INTO `ibetyou`.`bet` (`challenger`, `challengee`, `description`, `points`)" \
                " VALUES ('#{challenger['id']}', '#{challengee['id']}', '#{params[:description]}', '#{params[:points]}')"
            mysql.close
            status 204
            body ''
          end
        end
      end
    end
  end
end

post '/signup' do
  mysql = Mysql.new 'localhost', 'root', 'pass'
  mysql.query \
    "INSERT INTO `ibetyou`.`user` (`email`,`password`) VALUES(" \
    "'#{params[:email]}', '#{params[:password]}'" \
  ")"
  mysql.close
  status 204
end

post '/login' do
  mysql = Mysql.new 'localhost', 'root', 'pass'
  rs = mysql.query \
    "SELECT `id` FROM `ibetyou`.`user` WHERE " \
    "`email`='#{params[:email]}' " \
    " AND `password`='#{params[:password]}'"
  if rs.num_rows === 0
    status 403
    body ''
  else
    token = (0...8).map { (65 + rand(26)).chr }.join
    mysql.query "UPDATE `ibetyou`.`user` SET `token`='#{token}' WHERE `email`='#{params[:email]}'"
    headers 'X-Token' => token
    status 201
  end
  mysql.close
end

post '/bet/accept/:id' do
  mysql = Mysql.new 'localhost', 'root', 'pass'
  if params[:token].nil?
    status 403
    body ''
  else
    rs = mysql.query \
      "SELECT * FROM `ibetyou`.`user` WHERE `token`='#{params[:token]}'"
    if rs.num_rows === 0
      mysql.close
      status 403
      body ''
    else
      user = rs.fetch_hash
      if params[:id].nil?
        mysql.close
        status 400
        result = {'error' => 'missing bet id'}
        body result.to_json
      else
        rs = mysql.query "SELECT * FROM `ibetyou`.`bet` WHERE `id`=#{params[:id]}"
        if rs.num_rows === 0
          mysql.close
          status 404
          body ''
        else
          bet = rs.fetch_hash
          if user['id'] != bet['challengee']
            mysql.close
            status 403
            result = {'error' => 'You are not the challengee'}
            body result.to_json
          elsif bet['status'] != 'new'
            mysql.close
            status 400
            result = {'error' => 'Bet already underway or finished'}
            body result.to_json
          else
            mysql.query "UPDATE `ibetyou`.`bet` SET `status`='accepted' WHERE `id`=#{params[:id]}"
            mysql.query \
              "UPDATE `ibetyou`.`user` SET `points`=`points`-#{bet['points']} " \
              " WHERE `id`=#{user['id']}"
            mysql.close
            status 204
            body ''
          end
        end
      end
    end
  end
end

post '/bet/won/:id' do
  mysql = Mysql.new 'localhost', 'root', 'pass'
  if params[:token].nil?
    status 403
    body ''
  else
    rs = mysql.query \
      "SELECT * FROM `ibetyou`.`user` WHERE `token`='#{params[:token]}'"
    if rs.num_rows === 0
      mysql.close
      status 403
      body ''
    else
      user = rs.fetch_hash
      if params[:id].nil?
        mysql.close
        status 400
        result = {'error' => 'missing bet id'}
        body result.to_json
      else
        rs = mysql.query "SELECT * FROM `ibetyou`.`bet` WHERE `id`=#{params[:id]}"
        if rs.num_rows === 0
          mysql.close
          status 404
          body ''
        else
          bet = rs.fetch_hash
          if bet['challenger'] == user['id'] && bet['status'] != 'accepted'
            status 404
            result = {"error" => 'bet in wrong state'}
            body result.to_json
          elsif bet['challengee'] == user['id'] && bet['status_challengee'] != :nil
            status 404
            result = {"error" => 'bet in wrong state'}
            body result.to_json
          else
            if bet['challenger'] == user['id']
              mysql.query "UPDATE `ibetyou`.`bet` SET `status`='won' WHERE `id`=#{bet['id']}"
              if bet['status_challengee'] == 'lost'
                # todo bien
                mysql.query \
                  "UPDATE `ibetyou`.`user` SET `points`=`points`+#{bet['points'].to_i * 2} " \
                  " WHERE `id`=#{user['id']}"
                  status 201
                  body ''
              elsif bet['status_challengee'] == 'won'
                mysql.query "UPDATE `ibetyou`.`bet` SET `status`='draw' WHERE `id`=#{bet['id']}"
                mysql.query "UPDATE `ibetyou`.`bet` SET `status_challengee`='draw' WHERE `id`=#{bet['id']}"
                # draw
                mysql.query \
                  "UPDATE `ibetyou`.`user` SET `points`=`points`+#{bet['points']} " \
                  " WHERE `id`=#{bet['challenger']}"
                mysql.query \
                  "UPDATE `ibetyou`.`user` SET `points`=`points`+#{bet['points']} " \
                  " WHERE `id`=#{bet['challengee']}"
                  status 201
                  body ''
              else
                puts "what?"
                status 500
                body ''
              end
            elsif bet['challengee'] == user['id']
              mysql.query "UPDATE `ibetyou`.`bet` SET `status_challengee`='won' WHERE `id`=#{bet['id']}"
              if bet['status'] == 'lost'
                # todo bien
                mysql.query \
                  "UPDATE `ibetyou`.`user` SET `points`=`points`+#{bet['points'].to_i * 2} " \
                  " WHERE `id`=#{user['id']}"
                  status 201
                  body ''
              elsif bet['status'] == 'won'
                mysql.query \
                  "UPDATE `ibetyou`.`user` SET `points`=`points`+#{bet['points']} " \
                  " WHERE `id`=#{bet['challenger']}"
                mysql.query \
                  "UPDATE `ibetyou`.`user` SET `points`=`points`+#{bet['points']} " \
                  " WHERE `id`=#{bet['challengee']}"
                  status 201
                  body ''
              else
                puts "what?"
                status 500
                body ''
              end
            else
              status 403
              result = {"error" => "you're not involved in this bet"}
              body result.to_json
            end
          end
        end
      end
    end
  end
end

post '/bet/lost/:id' do
  mysql = Mysql.new 'localhost', 'root', 'pass'
  if params[:token].nil?
    status 403
    body ''
  else
    rs = mysql.query \
      "SELECT * FROM `ibetyou`.`user` WHERE `token`='#{params[:token]}'"
    if rs.num_rows === 0
      mysql.close
      status 403
      body ''
    else
      user = rs.fetch_hash
      if params[:id].nil?
        mysql.close
        status 400
        result = {'error' => 'missing bet id'}
        body result.to_json
      else
        rs = mysql.query "SELECT * FROM `ibetyou`.`bet` WHERE `id`=#{params[:id]}"
        if rs.num_rows === 0
          mysql.close
          status 404
          body ''
        else
          bet = rs.fetch_hash
          if bet['status'] != 'accepted'
            status 404
            result = {"error" => 'bet in wrong state'}
            body result.to_json
          elsif bet['challengee'] == user['id'] && bet['status_challengee'] != :nil
            status 404
            result = {"error" => 'bet in wrong state'}
            body result.to_json
          else
            if bet['challenger'] == user['id']
              mysql.query "UPDATE `ibetyou`.`bet` SET `status`='lost' WHERE `id`=#{bet['id']}"
              if bet['status_challengee'] == 'won'
                # todo bien
                mysql.query \
                  "UPDATE `ibetyou`.`user` SET `points`=`points`+#{bet['points'].to_i * 2} " \
                  " WHERE `id`=#{user['id']}"
                  status 201
                  body ''
              elsif bet['status_challengee'] == 'lost'
                # draw
                mysql.query "UPDATE `ibetyou`.`bet` SET `status`='draw' WHERE `id`=#{bet['id']}"
                mysql.query "UPDATE `ibetyou`.`bet` SET `status_challengee`='draw' WHERE `id`=#{bet['id']}"
                mysql.query \
                  "UPDATE `ibetyou`.`user` SET `points`=`points`+#{bet['points']} " \
                  " WHERE `id`=#{bet['challenger']}"
                mysql.query \
                  "UPDATE `ibetyou`.`user` SET `points`=`points`+#{bet['points']} " \
                  " WHERE `id`=#{bet['challengee']}"
                  status 201
                  body ''
              else
                puts "what?"
                status 500
                body ''
              end
            elsif bet['challengee'] == user['id']
              mysql.query "UPDATE `ibetyou`.`bet` SET `status_challengee`='lost' WHERE `id`=#{bet['id']}"
              if bet['status'] == 'won'
                # todo bien
                mysql.query \
                  "UPDATE `ibetyou`.`user` SET `points`=`points`+#{bet['points'].to_i * 2} " \
                  " WHERE `id`=#{user['id']}"
                  status 201
                  body ''
              elsif bet['status'] == 'lost'
                mysql.query \
                  "UPDATE `ibetyou`.`user` SET `points`=`points`+#{bet['points']} " \
                  " WHERE `id`=#{bet['challenger']}"
                mysql.query \
                  "UPDATE `ibetyou`.`user` SET `points`=`points`+#{bet['points']} " \
                  " WHERE `id`=#{bet['challengee']}"
                  status 201
                  body ''
              else
                puts "what?"
                status 500
                body ''
              end
            else
              status 403
              result = {"error" => "you're not involved in this bet"}
              body result.to_json
            end
          end
        end
      end
    end
  end
end

post '/bet/reject/:id' do
  mysql = Mysql.new 'localhost', 'root', 'pass'
  if params[:token].nil?
    status 403
    body ''
  else
    rs = mysql.query \
      "SELECT * FROM `ibetyou`.`user` WHERE `token`='#{params[:token]}'"
    if rs.num_rows === 0
      mysql.close
      status 403
      body ''
    else
      user = rs.fetch_hash
      if params[:id].nil?
        mysql.close
        status 400
        result = {'error' => 'missing bet id'}
        body result.to_json
      else
        rs = mysql.query "SELECT * FROM `ibetyou`.`bet` WHERE `id`=#{params[:id]}"
        if rs.num_rows === 0
          mysql.close
          status 404
          body ''
        else
          bet = rs.fetch_hash
          if user['id'] != bet['challengee']
            mysql.close
            status 403
            result = {'error' => 'You are not the challengee'}
            body result.to_json
          elsif bet['status'] != 'new'
            mysql.close
            status 400
            result = {'error' => 'Bet already underway or finished'}
            body result.to_json
          else
            rs = mysql.query "SELECT * FROM `ibetyou`.`user` WHERE `id`=#{bet['challenger']}"
            challenger = rs.fetch_hash
            mysql.query "UPDATE `ibetyou`.`bet` SET `status`='rejected' WHERE `id`=#{params[:id]}"
            mysql.query \
              "UPDATE `ibetyou`.`user` SET `points`=`points`+#{bet['points']} " \
              " WHERE `id`=#{challenger['id']}"
            mysql.close
            status 204
            body ''
          end
        end
      end
    end
  end
end
