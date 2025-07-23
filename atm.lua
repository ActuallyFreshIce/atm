-- ATM Interface Script for ComputerCraft: Tweaked

-- Auto-install to startup.lua on first run
if not fs.exists("startup.lua") then
    local f = fs.open("startup.lua", "w")
    f.write('shell.run("atm.lua")')
    f.close()
end

local SECRET_KEY = "UltraSecretKey123"

-- Simple SHA-256 implementation (pure Lua)
-- based on public domain code
local function sha256(msg)
    local band, bor, bxor, bnot, rshift, rrotate = bit32.band, bit32.bor, bit32.bxor, bit32.bnot, bit32.rshift, bit32.rrotate
    local K = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
    }
    local H = {
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19,
    }
    local function str2hexa(s)
        return (s:gsub('.', function(c) return string.format('%02x', c:byte()) end))
    end
    local msgLen = #msg * 8
    msg = msg .. string.char(0x80)
    local padLen = (56 - (#msg % 64)) % 64
    msg = msg .. string.rep('\0', padLen) .. string.pack('>I8', msgLen)
    for chunkStart=1,#msg,64 do
        local w = {}
        local chunk = msg:sub(chunkStart, chunkStart+63)
        for i=1,16 do
            w[i] = string.unpack('>I4', chunk:sub((i-1)*4+1, i*4))
        end
        for i=17,64 do
            local s0 = bxor(rrotate(w[i-15],7), rrotate(w[i-15],18), rshift(w[i-15],3))
            local s1 = bxor(rrotate(w[i-2],17), rrotate(w[i-2],19), rshift(w[i-2],10))
            w[i] = (w[i-16] + s0 + w[i-7] + s1) % 2^32
        end
        local a,b,c,d,e,f,g,h = table.unpack(H)
        for i=1,64 do
            local S1 = bxor(rrotate(e,6), rrotate(e,11), rrotate(e,25))
            local ch = bxor(band(e,f), band(bnot(e), g))
            local temp1 = (h + S1 + ch + K[i] + w[i]) % 2^32
            local S0 = bxor(rrotate(a,2), rrotate(a,13), rrotate(a,22))
            local maj = bxor(band(a,b), band(a,c), band(b,c))
            local temp2 = (S0 + maj) % 2^32
            h = g
            g = f
            f = e
            e = (d + temp1) % 2^32
            d = c
            c = b
            b = a
            a = (temp1 + temp2) % 2^32
        end
        H[1] = (H[1] + a) % 2^32
        H[2] = (H[2] + b) % 2^32
        H[3] = (H[3] + c) % 2^32
        H[4] = (H[4] + d) % 2^32
        H[5] = (H[5] + e) % 2^32
        H[6] = (H[6] + f) % 2^32
        H[7] = (H[7] + g) % 2^32
        H[8] = (H[8] + h) % 2^32
    end
    local digest = string.pack('>I4I4I4I4I4I4I4I4',
        H[1],H[2],H[3],H[4],H[5],H[6],H[7],H[8])
    return str2hexa(digest)
end

-- XOR uses SECRET_KEY directly. SHA-256 is retained for other hashing needs.
local XOR_KEY = SECRET_KEY

local function xorStr(data, key)
    local out = {}
    local klen = #key
    for i=1,#data do
        local kb = key:byte(((i-1) % klen) + 1)
        out[i] = string.char(bit32.bxor(data:byte(i), kb))
    end
    return table.concat(out)
end

local drive = peripheral.find("drive")
if not drive then error("Disk drive not found") end

local monitor = peripheral.find("monitor")
if not monitor then error("Monitor not found") end
monitor.setTextScale(1)
local mw, mh = monitor.getSize()

local account

local CURRENCY = {
    ["minecraft:iron_nugget"] = 0.5,
    ["minecraft:iron_ingot"] = 5,
    ["minecraft:iron_block"] = 45,
    ["minecraft:gold_nugget"] = 1,
    ["minecraft:gold_ingot"] = 10,
    ["minecraft:gold_block"] = 90,
    ["minecraft:emerald"] = 40,
    ["minecraft:diamond"] = 50,
    ["$1 Note"] = 1,
    ["$5 Note"] = 5,
    ["$10 Note"] = 10,
    ["$20 Note"] = 20,
    ["$50 Note"] = 50,
    ["$100 Note"] = 100,
    ["$1000 Note"] = 1000,
}

local function loadAccount()
    local diskID = drive.getDiskID()
    if not diskID then
        return nil, "No disk present"
    end
    local f = fs.open("/disk/account.dat", "rb")
    if not f then
        return nil, "account.dat missing"
    end
    local enc = f.readAll()
    f.close()
    local dec = xorStr(enc, XOR_KEY)
    local data = textutils.unserialize(dec)
    if type(data) ~= "table" then
        return nil, "Invalid account data"
    end
    if type(data.name) ~= "string" or type(data.id) ~= "string" or
       type(data.debit) ~= "number" or type(data.fare_uses) ~= "number" or
       type(data.disk_id) ~= "number" then
        return nil, "Account structure error"
    end
    if data.disk_id ~= diskID then
        return nil, "Card mismatch"
    end
    account = data
    print(string.format("[DEBUG] Account loaded: %s balance $%.2f", account.name, account.debit))
    return true
end

local function saveAccount()
    local data = textutils.serialize(account)
    local enc = xorStr(data, XOR_KEY)
    local f = fs.open("/disk/account.dat", "wb")
    f.write(enc)
    f.close()
    print("[DEBUG] Account saved")
end

local function center(text, y)
    local x = math.floor((mw - #text) / 2) + 1
    monitor.setCursorPos(x, y)
    monitor.write(text)
end

local buttons = {}
local function addButton(name, x,y,w,h)
    buttons[name] = {x=x,y=y,w=w,h=h}
end

local function drawButton(name, label)
    local b = buttons[name]
    for i=0,b.h-1 do
        monitor.setCursorPos(b.x, b.y+i)
        monitor.write(string.rep(" ", b.w))
    end
    monitor.setCursorPos(b.x + math.floor((b.w-#label)/2), b.y+math.floor(b.h/2))
    monitor.write(label)
end

local function inButton(name, x, y)
    local b = buttons[name]
    return x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h
end

local function clearMon()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    monitor.setCursorPos(1,1)
end

local function drawMain()
    clearMon()
    center("Welcome, "..account.name, 2)
    center(string.format("Balance: $%.2f", account.debit), 3)
    drawButton("deposit", "Deposit")
    drawButton("withdraw", "Withdraw")
    drawButton("eject", "Eject Disk")
end

-- withdraw UI
local function withdrawUI()
    local amount = 1
    local plus = {x=2,y=4,w=3,h=3}
    local minus = {x=6,y=4,w=3,h=3}
    local enter = {x=10,y=4,w=7,h=3}
    while true do
        clearMon()
        center("Withdraw Amount", 2)
        center("$"..amount,3)
        monitor.setCursorPos(plus.x, plus.y); monitor.write("[+]")
        monitor.setCursorPos(minus.x, minus.y); monitor.write("[-]")
        monitor.setCursorPos(enter.x, enter.y); monitor.write("[Enter]")
        local e, side, x, y = os.pullEvent("monitor_touch")
        if x >= plus.x and x <= plus.x+plus.w and y >= plus.y and y <= plus.y+plus.h then
            amount = math.min(1000, amount + 1)
        elseif x >= minus.x and x <= minus.x+minus.w and y >= minus.y and y <= minus.y+minus.h then
            amount = math.max(1, amount - 1)
        elseif x >= enter.x and x <= enter.x+enter.w and y >= enter.y and y <= enter.y+enter.h then
            return amount
        end
    end
end

local function dispenseCurrency(amount)
    local inventory = {}
    for slot=1,16 do
        local detail = turtle.getItemDetail(slot)
        if detail then
            local val = CURRENCY[detail.name] or CURRENCY[detail.label]
            if val then
                inventory[#inventory+1] = {slot=slot,value=val,count=detail.count}
            end
        end
    end
    table.sort(inventory, function(a,b) return a.value > b.value end)
    local need = amount
    local actions = {}
    for _,item in ipairs(inventory) do
        while item.count > 0 and need >= item.value do
            need = need - item.value
            table.insert(actions, item.slot)
            item.count = item.count - 1
        end
    end
    if need ~= 0 then
        print("[DEBUG] Withdraw failure: cannot make exact change")
        return false
    end
    for _,slot in ipairs(actions) do
        turtle.select(slot)
        turtle.drop()
        print("[DEBUG] Dispensed from slot "..slot)
    end
    turtle.select(1)
    return true
end

local function withdraw()
    local amount = withdrawUI()
    print("[DEBUG] Balance before withdraw: $"..account.debit)
    if amount > account.debit then
        print("[DEBUG] Withdraw failure: insufficient funds")
        return
    end
    if dispenseCurrency(amount) then
        account.debit = account.debit - amount
        print("[DEBUG] Balance after withdraw: $"..account.debit)
        saveAccount()
    end
end

local function deposit()
    print("[DEBUG] Balance before deposit: $"..account.debit)
    for slot=1,16 do
        turtle.select(slot)
        turtle.suck()
        local detail = turtle.getItemDetail(slot)
        if detail then
            local val = CURRENCY[detail.name] or CURRENCY[detail.label]
            if val then
                account.debit = account.debit + val * detail.count
            else
                turtle.drop()
            end
        end
    end
    turtle.select(1)
    print("[DEBUG] Balance after deposit: $"..account.debit)
    saveAccount()
end

-- Setup buttons
addButton("deposit", 2, mh-3, 10, 3)
addButton("withdraw", mw/2-5, mh-3, 10, 3)
addButton("eject", mw-11, mh-3, 10, 3)

local function waitForDisk()
    while not drive.isDiskPresent() do
        print("Insert card...")
        os.pullEvent("disk")
    end
    print("[DEBUG] Disk insert")
end

while true do
    waitForDisk()
    local ok, err = loadAccount()
    if not ok then
        print("[ERROR] " .. err)
        drive.ejectDisk()
        sleep(1)
    else
        drawMain()
        while true do
            local e, side, x, y = os.pullEvent()
            if e == "monitor_touch" then
                if inButton("deposit", x, y) then
                    deposit()
                    drawMain()
                elseif inButton("withdraw", x, y) then
                    withdraw()
                    drawMain()
                elseif inButton("eject", x, y) then
                    drive.ejectDisk()
                    print("[DEBUG] Disk ejected")
                    account = nil
                    clearMon()
                    break
                end
            elseif e == "disk" and not drive.isDiskPresent() then
                print("[DEBUG] Disk removed")
                account = nil
                clearMon()
                break
            end
        end
    end
end

