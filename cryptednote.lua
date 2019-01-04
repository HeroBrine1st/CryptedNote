local crypt = require("crypt")
local component = require("component")
local computer = require("computer")
local unicode = require("unicode")
local gpu = component.gpu
local fs = require("filesystem")
local term = require("term")
local event = require("event")
local shell = require("shell")
local dir = "/usr/cryptednote/"
local tmp = {}
local args,options = shell.parse(...)

local function parts(str,partLen)
  local i = 1
  local len = unicode.len(str)
  return function()
    if i > len then return nil end
    local part = unicode.sub(str,i,i+partLen-1)
    i = i+partLen
    return part
  end
end

local function writeFile(path,data)
  local handle, reason = io.open(path,"w")
  if not handle then return nil, reason end
  for part in parts(data,1024) do
    handle:write(part)
  end
  handle:close()
  return true
end

local function readFile(path)
  local handle, reason = io.open(path,"r")
  if not handle then return nil, reason end
  local buffer = ""
  for line in handle:lines() do
    buffer = buffer .. line .. "\n"
  end
  handle:close()
  return buffer
end

local function readFileStandart(path)
  local handle, reason = io.open(path,"r")
  if not handle then return nil, reason end
  local buffer = ""
  repeat
    local data,reason = handle:read()
    if data then buffer = buffer .. data end
    if not data and reason then handle:close() return nil, reason end
  until not data
  handle:close()
  return buffer
end

local function write(text)
  local _, y = term.getCursor()
  term.setCursor(1,y-1)
  print(text)
end

local function encrypt(str,key)
  local crypted = ""
  local i = 0
  local _parts = math.ceil(unicode.len(str)/128)
  for part in parts(str,128) do
    i = i + 1
    crypted = crypted .. crypt.crypt(part,key)
    write("Encrypting in process. Part " .. tostring(i) .. "/" .. tostring(_parts))
    computer.pullSignal(0)
  end
  return crypted
end



local function decrypt(str,key)
  local uncrypted = ""
  local i = 0
  local _parts = math.ceil(#str/256)
  for part in parts(str,256) do
    i = i + 1
    uncrypted = uncrypted .. crypt.decrypt(part,key) 
    write("Decrypting in process. Part " .. tostring(i) .. "/" .. tostring(_parts))
    computer.pullSignal(0)
  end
  return uncrypted:gsub("\0","")
end


local function edit(path,rewrite)
  term.clear()
  if not fs.exists(path) or rewrite then writeFile(path,crypt.crypt("--ваша новая заметка--",tmp.keys)) end
  local tmpname = fs.concat(dir,"temp.crtnt")
  do
    local buffer = readFileStandart(path)
    writeFile(tmpname,decrypt(buffer,tmp.keys))
  end
  os.execute("edit " .. tmpname)
  do
    local buffer1 = readFile(tmpname)
    os.remove(tmpname)
    writeFile(path,encrypt(buffer1,tmp.keys))
  end
end
fs.makeDirectory(dir)

if fs.exists(fs.concat(dir,"password.md5")) then
  tmp.md5 = readFileStandart(fs.concat(dir,"password.md5"))
end
local str = "Введите пароль: "
if not tmp.md5 then str = "Введите новый пароль: " end
local crtd = false
while not tmp.keys do
  io.write(str)
  local psk = term.read(_,_,_,"•")
  if not psk then print("Выход") os.exit() end
  print("\nВычисление контрольной суммы...")
  local checksum = crypt.md5(psk)
  write("Вычисление контрольной суммы... Контрольная сумма вычислена")
  if tmp.md5 then 
    print("Сравнение контрольных сумм... ")
    if tmp.md5 == crypt.md5(psk) then 
      write("Сравнение контрольных сумм...  Пароль верный")
      print("Создание таблицы ключей...") 
      tmp.keys = crypt.getkey(psk) 
      write("Создание таблицы ключей... Таблица ключей создана")
    else
      write("Сравнение контрольных сумм... Неверный пароль.")
      os.sleep(0.5)
      os.exit()
    end
  else
    print("Форматирование и запись контрольной суммы в файл")
    for file in fs.list(dir) do
      print("Удаление " .. file)
      fs.remove(fs.concat(dir,file))
    end
    tmp.md5 = crypt.md5(psk)
    writeFile(fs.concat(dir,"password.md5"),tmp.md5)
    print("Создание таблицы ключей...")
    tmp.keys = crypt.getkey(psk)
    write("Создание таблицы ключей... Таблица ключей создана.")
    crtd = true
  end
  psk = nil
  os.sleep(0.5)
end
if crtd then
  print("Добро пожаловать в программу cryptednote")
  print("В целях безопасности названия ваших файлов будут защищены хеш-функцией MD5, а их содержимое будет зашифровано паролем, введенном при запуске программы.")
  print("Не передавайте пароль третьим лицам. В случае угрозы безопасности или невозможности ввода пароля удалите файл " .. dir .. "password.md5 , запомнив его содержимое")
  print("Клик для продолжения")
  event.pull("touch")
end
print("Начинается работа с файлом")
if not args[1] then print("Не получено название файла, возврат в консоль.") os.exit() end
local pathmd5 = crypt.md5(args[1])
local path = fs.concat(dir,pathmd5)
if options.execute or options.x then
  local buffer = readFileStandart(path)
  local file = decrypt(buffer,tmp.keys) -- :sub(1,-9)
  local f, r = load(file)
  if f then 
    xpcall(f,function(err)
      print("Error in file: " .. path)
      print("Error code: " .. err)
    end)
  else
    print("Couldn't load file:" .. path)
    print("Error code:" .. r)
  end
else
  edit(path,options.rewrite or options.w)
end
