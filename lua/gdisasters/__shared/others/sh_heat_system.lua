GridMap = {}
cellsToUpdate = {}
waterSources = {}
LandSources = {}
Cloud = {}

-- Tamaño de la cuadrícula y rango de temperatura
local gridSize = 5000 -- Tamaño de cada cuadrado en unidades

local minTemperature = -44 -- Temperatura mínima
local maxTemperature = 44 -- Temperatura máxima
local minHumidity = 0 -- Humedad mínima
local maxHumidity = 100 -- Humedad máxima
local minPressure = 94000 -- Presión mínima en milibares
local maxPressure = 106000 -- Presión máxima en milibares
local minAirflow = 0 -- Presión mínima en milibares
local maxAirflow = 10000 -- Presión máxima en milibares

local updateInterval = 0.1 -- Intervalo de actualización en segundos
local updateBatchSize = 500 -- Número de celdas a actualizar por frame
local nextUpdateGrid = CurTime()
local nextUpdateGridPlayer = CurTime()
local nextUpdateWeather = CurTime()
local nextThunderThink = CurTime()

local tempdiffusionCoefficient = 0.01
local HumidityDiffusionCoefficient = 0.01
local solarInfluenceCoefficient = 0.01
local AirflowCoefficient = 0.01
local coolingFactor = 0.5
local nighttimeHumidityIncrease = 0.05
local gas_constant = 8.314 -- J/(mol·K)
local specific_heat_vapor = 1.996 -- J/(g·K)


local waterTemperatureEffect = 0.01   -- El agua tiende a mantener una temperatura más constante
local landTemperatureEffect = 0.04     -- La tierra se calienta y enfría más rápido que el agua
local waterHumidityEffect = 0.05       -- El agua puede aumentar significativamente la humedad en su entorno
local landHumidityEffect = 0.05        -- La tierra puede retener menos humedad que el agua
local mountainTemperatureEffect = -0.03  -- Las montañas tienden a ser más frías debido a la altitud
local mountainHumidityEffect = 0.04    -- Las montañas pueden influir moderadamente en la humedad debido a las corrientes de aire

local convergenceThreshold = 0.5
local strongStormThreshold = 2.0
local hailThreshold = 1.5
local rainThreshold = 1.0
local cloudThreshold = 0.5
local stormTemperatureThreshold = 30 -- Umbral de temperatura para la generación de tormentas
local stormPressureThreshold = 10000 -- Umbral de presión para la generación de tormentas
local lowTemperatureThreshold = 10
local lowHumidityThreshold = 40 -- Umbral de humedad para la formación de nubes
local convergenceFactor = 0.001
local temperatureThreshold = 20
local humidityThreshold = 75
local MaxClouds = 5
local MaxRainDrop = 1
local MaxHail = 1
local cloudDensityCoefficient = 0.01  -- Coeficiente para convertir humedad en densidad de nubes
local freezingTemperature = 0

local condensationLatentHeat = 25  -- Reduciendo el valor a un nivel más razonable
local freezingLatentHeat = 33  -- Mantenemos este valor para el calor latente de congelación
local stormLatentHeatThreshold = 10  -- Ajustamos este valor a uno más bajo para una formación de tormenta más realista
local hailLatentHeatThreshold = 20  -- Ajustamos este valor también a uno más bajo

local maxDrawDistance = 100000

-- Function to calculate latent heat released during condensation
local function calculateCondensationLatentHeat(cloudDensity)
    return cloudDensity * condensationLatentHeat
end

-- Function to calculate latent heat released during freezing
local function calculateFreezingLatentHeat(cloudDensity)
    return cloudDensity * freezingLatentHeat
end
-- Función para normalizar un vector

-- Función para calcular la radiación solar
function CalculateSolarRadiation(cellPosition, sunDirection)
    if not sunDirection or not cellPosition then
        return 0  -- Si falta alguna dirección, no hay radiación solar
    end

    -- Calcular la altura solar (ángulo entre la dirección del sol y el eje Y)
    local solarAltitude = math.acos(sunDirection.y)
    
    -- Verificar si el sol está por encima del horizonte
    if solarAltitude <= 0 then
        return 0  -- Si el sol está debajo del horizonte, no hay radiación solar
    end

    -- Normalizar la dirección del sol y la posición de la celda
    local normalizedCellPosition = cellPosition:Normalize()

    if not normalizedCellPosition then
        return 0  -- Si la normalización falla, no hay radiación solar
    end

    local angleToSun = math.acos(sunDirection:Dot(normalizedCellPosition))

    -- Asumir que la radiación solar disminuye linealmente con el ángulo
    local solarRadiation = math.cos(angleToSun)

    return solarRadiation
end

function CalculateTemperature(x, y, z)
    local totalTemperature = 0
    local totalAirFlow = 0
    local count = 0

    local currentCell = GridMap[x][y][z]

    for dx = -1, 1 do
        for dy = -1, 1 do
            for dz = -1, 1 do
                local nx, ny, nz = x + dx * gridSize, y + dy * gridSize, z + dz * gridSize
                if GridMap[nx] and GridMap[nx][ny] and GridMap[nx][ny][nz] then
                    local neighborCell = GridMap[nx][ny][nz]
                    if neighborCell.temperature and neighborCell.Airflow then
                        totalTemperature = totalTemperature + neighborCell.temperature
                        totalAirFlow = totalAirFlow + neighborCell.Airflow
                        count = count + 1
                    end
                end
            end
        end
    end

    if count == 0 then return GridMap[x][y][z].temperature or 0 end

    local averageTemperature = totalTemperature / count
    local averageAirFlow = totalAirFlow / count
    local temperatureInfluence = 0  -- Inicializamos en 0

    -- Obtener la dirección del sol y calcular la radiación solar
    local sunDirection = gDisasters_GetSunDir() or gDisasters_GetSunEnvDir()
    local solarRadiation = CalculateSolarRadiation(Vector(x, y, z), sunDirection)
    local solarInfluence = solarRadiation * solarInfluenceCoefficient
    local coolingEffect = 0
    if sunDirection or solarInfluence > 0 then
        temperatureInfluence = GridMap[x][y][z].temperatureInfluence or 0  -- Aplicamos solo si hay sol 
    else
        coolingEffect = -coolingFactor
    end
    
    local currentTemperature = GridMap[x][y][z].temperature or 0

    -- Adding latent heat release
    local cloudDensity = GridMap[x][y][z].cloudDensity or 0
    local latentHeat = 0
    if cloudDensity > 0 then
        if currentTemperature > freezingTemperature then
            latentHeat = calculateCondensationLatentHeat(cloudDensity)
        else
            latentHeat = calculateFreezingLatentHeat(cloudDensity)
        end
    end

    
    local AirflowEffect = AirflowCoefficient * averageAirFlow
    local temperatureChange = tempdiffusionCoefficient * (averageTemperature - currentTemperature)
    local newTemperature = math.Clamp(currentTemperature + temperatureChange + AirflowEffect + temperatureInfluence + solarInfluence + coolingEffect + latentHeat, minTemperature, maxTemperature)
    
    return newTemperature
end

function CalculateHumidity(x, y, z)
    local totalHumidity = 0
    local totalAirFlow = 0
    local count = 0

    local currentCell = GridMap[x][y][z]

    for dx = -1, 1 do
        for dy = -1, 1 do
            for dz = -1, 1 do
                local nx, ny, nz = x + dx * gridSize, y + dy * gridSize, z + dz * gridSize
                if GridMap[nx] and GridMap[nx][ny] and GridMap[nx][ny][nz] then
                    local neighborCell = GridMap[nx][ny][nz]
                    if neighborCell.humidity and neighborCell.Airflow then
                        totalHumidity = totalHumidity + neighborCell.humidity
                        totalAirFlow = totalAirFlow + neighborCell.Airflow
                        count = count + 1
                    end
                end
            end
        end
    end

    if count == 0 then return GridMap[x][y][z].humidity or 0 end

    local averageHumidity = totalHumidity / count
    local averageAirFlow = totalAirFlow / count
    local humidityInfluence = 0

    -- Obtener la dirección del sol y calcular la radiación solar
    local sunDirection = gDisasters_GetSunDir() or gDisasters_GetSunEnvDir()
    local solarRadiation = CalculateSolarRadiation(Vector(x, y, z), sunDirection)
    local solarHumidityInfluence = solarRadiation * solarInfluenceCoefficient
    local coolingHumidityEffect = 0
    if sunDirection or solarHumidityInfluence > 0 then
        humidityInfluence = GridMap[x][y][z].humidityInfluence or 0
    else
        coolingHumidityEffect = nighttimeHumidityIncrease
    end


    local currentHumidity = GridMap[x][y][z].humidity or 0
    local AirflowEffect = AirflowCoefficient * averageAirFlow
    local humidityChange = HumidityDiffusionCoefficient * (averageHumidity - currentHumidity)
    local newHumidity = math.Clamp(currentHumidity + humidityChange + AirflowEffect + humidityInfluence + solarHumidityInfluence + coolingHumidityEffect,minHumidity,maxHumidity)

    return newHumidity
end



-- Función para calcular la presión de una celda basada en temperatura y humedad
function CalculatePressure(x, y, z)
    local cell = GridMap[x][y][z]
    if not cell then return 0 end -- Si la celda no existe, retornar 0

    local temperature = cell.temperature or 0 
    
    if temperature == 0 then
        temperature = 0.01 -- Ajuste mínimo para evitar división por cero
    end

    local humidity = cell.humidity or 0

    -- Calcular la presión basada en la temperatura y la humedad
    local newpressure = math.Clamp((gas_constant * temperature * (1 + ((specific_heat_vapor * humidity) / temperature))) * 100, minPressure,maxPressure)

    -- Asegurarse de que la presión esté dentro del rango
    return newpressure
end

function CalculateAirFlow(x, y, z)
    local totalDeltaPressureX = 0
    local totalDeltaPressureY = 0
    local totalDeltaPressureZ = 0

    local currentCell = GridMap[x][y][z]

    for dx = -1, 1 do
        for dy = -1, 1 do
            for dz = -1, 1 do
                local nx, ny, nz = x + dx * gridSize, y + dy * gridSize, z + dz * gridSize
                if GridMap[nx] and GridMap[nx][ny] and GridMap[nx][ny][nz] then
                    local neighborCell = GridMap[nx][ny][nz]
                    

                    local deltaPressure = neighborCell.pressure - currentCell.pressure

                    -- Sumar la diferencia de presión a los totales en cada eje
                    totalDeltaPressureX = totalDeltaPressureX + deltaPressure * dx
                    totalDeltaPressureY = totalDeltaPressureY + deltaPressure * dy
                    totalDeltaPressureZ = totalDeltaPressureZ + deltaPressure * dz
                end
            end
        end
    end
   
    -- Crear un vector de flujo de aire
    local airflowVector = Vector(totalDeltaPressureX, totalDeltaPressureY, totalDeltaPressureZ)

    -- Calcular la magnitud del flujo de aire
    local airflowMagnitude = math.sqrt(airflowVector.x^2 + airflowVector.y^2 + airflowVector.z^2)

    local newAirflow = math.Clamp(airflowMagnitude * AirflowCoefficient, minAirflow, maxAirflow)

    return newAirflow 
end

function CalculateAirFlowDirection(x, y, z)
    local totalDeltaPressureX = 0
    local totalDeltaPressureY = 0
    local totalDeltaPressureZ = 0

    local currentCell = GridMap[x][y][z]

    for dx = -1, 1 do
        for dy = -1, 1 do
            for dz = -1, 1 do
                local nx, ny, nz = x + dx * gridSize, y + dy * gridSize, z + dz * gridSize
                if GridMap[nx] and GridMap[nx][ny] and GridMap[nx][ny][nz] then
                    local neighborCell = GridMap[nx][ny][nz]

                    local deltaPressure = neighborCell.pressure - currentCell.pressure

                    -- Sumar la diferencia de presión a los totales en cada eje
                    totalDeltaPressureX = totalDeltaPressureX + deltaPressure * dx
                    totalDeltaPressureY = totalDeltaPressureY + deltaPressure * dy
                    totalDeltaPressureZ = totalDeltaPressureZ + deltaPressure * dz
                end
            end
        end
    end

    -- Crear un vector de flujo de aire
    local airflowVector = Vector(totalDeltaPressureX, totalDeltaPressureY, totalDeltaPressureZ)

    -- Calcular la magnitud del flujo de aire
    local airflowMagnitude = math.sqrt(airflowVector.x^2 + airflowVector.y^2 + airflowVector.z^2)

    -- Normalizar el vector de flujo de aire para obtener la dirección del viento
    local windDirection = Vector(0, 0, 0)
    if airflowMagnitude > 0 then
        windDirection.x = airflowVector.x / airflowMagnitude
        windDirection.y = airflowVector.y / airflowMagnitude
        windDirection.z = 0
    end

    return windDirection
end

function GetCellType(x, y, z)
    local MapBounds = getMapBounds()
    local max, min, floor = MapBounds[1], MapBounds[2], MapBounds[3]
    local minX, minY, maxZ = math.floor(min.x / gridSize) * gridSize, math.floor(min.y / gridSize) * gridSize,  math.ceil(min.z / gridSize) * gridSize
    local maxX, maxY, minZ = math.ceil(max.x / gridSize) * gridSize, math.ceil(max.y / gridSize) * gridSize,  math.floor(max.z / gridSize) * gridSize
    local floorz = math.floor(floor.z / gridSize) * gridSize

    -- Verificar si las coordenadas están dentro de los límites del mapa
    if x < minX or x >= maxX or y < minY or y >= maxY or z < minZ or z >= maxZ then
        return "out_of_bounds" -- Devolver un tipo especial para coordenadas fuera de los límites del mapa
    end
    
    local traceStart = Vector(x, y, z)
    local traceEnd = traceStart - Vector(0, 0, 10) 
    traceEnd.z = math.max(traceEnd.z, minZ)
    local tr = util.TraceLine( {
        startpos = traceStart,
        endpos = traceEnd,
        mask = MASK_WATER, -- Solo colisionar con agua
        filter = function(ent) return ent:IsValid() end  -- Filtrar cualquier entidad válida
    } )

    -- Si el trazado de línea colisiona con agua, la celda es de tipo "water"
    if tr.Hit then
        return "water"
    end

    local WATER_LEVEL = tr.HitPos.z
    local MOUNTAIN_LEVEL = floorz + 10000 -- Ajusta la altura de la montaña según sea necesario

    -- Simular diferentes tipos de celdas basadas en coordenadas
    if z <= WATER_LEVEL then
        return "water" -- Por debajo del nivel del agua es agua
    elseif z >= MOUNTAIN_LEVEL then
        return "mountain" -- Por encima del nivel de la montaña es montaña
    else
        return "land" -- En otras coordenadas es tierra
    end
end




-- Función para crear partículas de lluvia
function CreateRain(x, y, z)

    if #ents.FindByClass("env_spritetrail") > MaxRainDrop then return end

    local particle = ents.Create("env_spritetrail") -- Create a sprite trail entity for raindrop particle
    if not IsValid(particle) then return end -- Verifica si la entidad fue creada correctamente

    particle:SetPos(Vector(x, y, z)) -- Set the position of the particle
    particle:SetKeyValue("lifetime", "2") -- Set the lifetime of the particle
    particle:SetKeyValue("startwidth", "2") -- Set the starting width of the particle
    particle:SetKeyValue("endwidth", "0") -- Set the ending width of the particle
    particle:SetKeyValue("spritename", "effects/blood_core") -- Set the sprite name for the particle (you can use any sprite)
    particle:SetKeyValue("rendermode", "5") -- Set the render mode of the particle
    particle:SetKeyValue("rendercolor", "0 0 255") -- Set the color of the particle (blue for rain)
    particle:SetKeyValue("spawnflags", "1") -- Set the spawn flags for the particle
    particle:Spawn() -- Spawn the particle
    particle:Activate() -- Activate the particle

    timer.Simple(2, function() -- Remove the particle after 2 seconds
        if IsValid(particle) then particle:Remove() end
    end)
end

function UpdateCloudDensity(x, y, z)
    local currentCell = GridMap[x][y][z]
    local humidity = currentCell.humidity or 0

    if humidity > humidityThreshold then
        currentCell.cloudDensity = (humidity - humidityThreshold) * cloudDensityCoefficient
    else
        currentCell.cloudDensity = 0
    end
end

function CheckStormFormation(x, y, z)
    local currentCell = GridMap[x][y][z]
    local latentHeat = 0

    if currentCell.cloudDensity and currentCell.cloudDensity > 0 then
        if currentCell.temperature > freezingTemperature then
            latentHeat = calculateCondensationLatentHeat(currentCell.cloudDensity)
        else
            latentHeat = calculateFreezingLatentHeat(currentCell.cloudDensity)
        end
    end

    if latentHeat > stormLatentHeatThreshold then
        -- Trigger storm formation logic here
        CreateStorm(x, y, z)
    end
end

function CheckHailFormation(x, y, z)
    local currentCell = GridMap[x][y][z]
    local latentHeat = 0

    if currentCell.cloudDensity and currentCell.cloudDensity > 0 then
        if currentCell.temperature <= freezingTemperature then
            latentHeat = calculateFreezingLatentHeat(currentCell.cloudDensity)
        end
    end

    if latentHeat > hailLatentHeatThreshold then
        -- Trigger hail formation logic here
        CreateHail(x, y, z)
    end
end


function CreateLightningAndThunder(x,y,z)
    local startpos = Vector(x,y,z)
    local endpos = startpos - Vector(0, 0, 50000)
    local tr = util.TraceLine({
        start = startpos,
        endpos = endpos,
    })
    if HitChance(1) then
        CreateLightningBolt(startpos, tr.HitPos, {"purple", "blue"}, {"Grounded", "NotGrounded"})
    end

end

function SpawnCloud(pos, color)
    if #ents.FindByClass("gd_cloud_cumulus") > MaxClouds then return end

    local cloud = ents.Create("gd_cloud_cumulus")
    if not IsValid(cloud) then return end -- Verifica si la entidad fue creada correctamente

    cloud:SetPos(pos)
    cloud.DefaultColor = color
    cloud:SetModelScale(0.5, 0)
    cloud:Spawn()
    cloud:Activate()

    table.insert(Cloud, cloud)

    timer.Simple(cloud.Life, function()
        if IsValid(cloud) then cloud:Remove() end
    end)

    return cloud
    
end

-- Función para simular la formación y movimiento de nubes
function CreateCloud(x,y,z)
    local cell = GridMap[x][y][z]

    local humidity = cell.humidity
    local temperature = cell.temperature
    if humidity < lowHumidityThreshold and temperature < lowTemperatureThreshold then
        -- Generate clouds in cells with low humidity and temperature
        AdjustCloudBaseHeight(x, y, z)
        
        local baseHeight = cell.baseHeight or z
        local pos = Vector(x, y, baseHeight)
        local color = Color(255,255,255)
        
        SpawnCloud(pos, color)
        
        
    end
    
end

-- Función para simular la formación y movimiento de nubes
function CreateStorm(x,y,z)
    local cell = GridMap[x][y][z]

    local humidity = cell.humidity
    local temperature = cell.temperature
    if humidity < lowHumidityThreshold and temperature < lowTemperatureThreshold then
        AdjustCloudBaseHeight(x, y, z)

        -- Generate clouds in cells with low humidity and temperature
        local baseHeight = cell.baseHeight or z
        local pos = Vector(x, y, baseHeight)
        local color = Color(117,117,117)
        
        local cloud = SpawnCloud(pos, color)

        if not IsValid(cloud) then
            return
        end
        
        -- Crear rayo y trueno en intervalos regulares
        local lightningInterval = 10 -- Intervalo en segundos
        local lightningTimerName = "LightningTimer_" .. cloud:EntIndex()

        timer.Create(lightningTimerName, lightningInterval, 0, function()
            timer.Remove(lightningTimerName)
            CreateLightningAndThunder(pos.x, pos.y, pos.z)
        end)

       
        -- Detener el temporizador cuando la nube se elimina
        timer.Simple(cloud.Life, function()
            
            cloud:Remove()
            timer.Remove(lightningTimerName)
            
        end)

        
    end
    
end

function GetDistance(x1, y1, z1, x2, y2, z2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Función para obtener la distancia a la fuente más cercana
function GetClosestDistance(x, y, z, sources)
    local closestDistance = math.huge

    for _, source in ipairs(sources) do
        local distance = GetDistance(x, y, z, source.x, source.y, source.z)
        if distance < closestDistance then
            closestDistance = distance
        end
    end

    return closestDistance
end

function AddTemperatureHumiditySources()
    print("Adding Sources...")
    local waterSources = GetWaterSources()
    local landSources = GetLandSources()
    local mountainSources = GetMountainSources()

    for x, column in pairs(GridMap) do
        for y, row in pairs(column) do
            for z, cell in pairs(row) do
                local closestWaterDist = GetClosestDistance(x, y, z, waterSources)
                local closestLandDist = GetClosestDistance(x, y, z, landSources)
                local closestMountainDist = GetClosestDistance(x, y, z, mountainSources)


                -- Comparar distancias y ajustar temperatura, humedad y presión en consecuencia
                if closestWaterDist < closestLandDist and closestWaterDist < closestMountainDist then
                    cell.terrainType = "water"
                    cell.temperatureInfluence = -waterTemperatureEffect
                    cell.humidityInfluence = waterHumidityEffect
                elseif closestLandDist < closestMountainDist and closestLandDist < closestWaterDist then
                    cell.terrainType = "land"
                    cell.temperatureInfluence = landTemperatureEffect
                    cell.humidityInfluence = -landHumidityEffect
                else
                    cell.terrainType = "mountain"
                    cell.temperatureInfluence = mountainTemperatureEffect
                    cell.humidityInfluence = -mountainHumidityEffect
                end 
            end
        end
    end

    print("Adding Finish")
end

-- Función para obtener las coordenadas de las fuentes de agua
function GetWaterSources()
    local waterSources = {}

    for x, column in pairs(GridMap) do
        for y, row in pairs(column) do
            for z, cell in pairs(row) do
                local celltype = GetCellType(x, y, z)
                if celltype == "water" then
                    table.insert(waterSources, {x = x, y = y , z = z})
                end
            end
        end
    end

    return waterSources
end

-- Función para obtener las coordenadas de las fuentes de tierra
function GetLandSources()
    local landSources = {}

    for x, column in pairs(GridMap) do
        for y, row in pairs(column) do
            for z, cell in pairs(row) do
                local celltype = GetCellType(x, y, z)
                if celltype == "land" then
                    table.insert(landSources, {x = x, y = y , z = z})
                end
            end
        end
    end

    return landSources
end

function GetMountainSources()
    local MountainSources = {}

    for x, column in pairs(GridMap) do
        for y, row in pairs(column) do
            for z, cell in pairs(row) do
                local celltype = GetCellType(x, y, z)
                if celltype == "mountain" then
                    table.insert(MountainSources, {x = x, y = y , z = z})
                end
            end
        end
    end

    return MountainSources
end

function AdjustCloudBaseHeight(x,y,z)
    local nubegrid = GridMap[x][y][z]
    local humidity = nubegrid.humidity or 0
    local baseHeightAdjustment = (1 - humidity) * 0.1
    
    nubegrid.baseHeight = (nubegrid.baseHeight or 0) + baseHeightAdjustment
    return nubegrid.baseHeight
end

function SimulateRain()
    for x, column in pairs(GridMap) do
        for y, row in pairs(column) do
            for z, nubegrid in pairs(row) do
                CreateRain(x, y, z)

                local pressureIncreaseFactor = 0.2  -- Factor base de aumento de presión
                
                local originalTemperature = nubegrid.temperature or 0
                local originalHumidity = nubegrid.humidity or 0

                -- Cálculo de enfriamiento y aumento de presión basado en la humedad
                local humidityModifier = 1 - originalHumidity  -- Más seco = más enfriamiento y aumento de presión

                local temperatureChange = coolingFactor * humidityModifier
                local pressureChange = pressureIncreaseFactor * humidityModifier

                nubegrid.temperature = originalTemperature - temperatureChange
                nubegrid.pressure = (nubegrid.pressure or 0) + pressureChange


            end
        end
    end
end

function CreateHail(x, y, z)
    if #ents.FindByClass("gd_d1_hail_ch") > MaxHail then return end
    
    local hail = ents.Create("gd_d1_hail_ch")
    hail:SetPos(Vector(x, y, z))
    hail:Spawn()
    hail:Activate()

    timer.Simple(2, function() -- Remove the particle after 2 seconds
        if IsValid(hail) then hail:Remove() end
    end)
end

function SimulateHail()
    for x, column in pairs(GridMap) do
        for y, row in pairs(column) do
            for z, nubegrid in pairs(row) do

                if nubegrid.humidity > humidityThreshold and nubegrid.temperature < temperatureThreshold then
                    CreateHail(x, y, z)
                end
            end
        end
    end
end
function SimulateConvergence(x,y,z)
  
    local convergenceStrength = 0
    local airSpeedSum = 0
    local neighborCount = 0

    local cell = GridMap[x][y][z]

    for dx = -1, 1 do
        for dy = -1, 1 do
            for dz = -1, 1 do
                if not (dx == 0 and dy == 0 and dz == 0) then -- Evitar la celda actual
                    local nx, ny, nz = x + dx * gridSize, y + dy * gridSize, z + dz * gridSize
                    if GridMap[nx] and GridMap[nx][ny] and GridMap[nx][ny][nz] then
                        local neighborCell = GridMap[nx][ny][nz]
                        local airSpeed = math.abs((cell.pressure or 0) - (neighborCell.pressure or 0))
                        airSpeedSum = airSpeedSum + airSpeed
                        neighborCount = neighborCount + 1
                    end
                end
            end
        end
    end

    if neighborCount > 0 then
        convergenceStrength = airSpeedSum / neighborCount

        if convergenceStrength > convergenceThreshold then
            if convergenceStrength > strongStormThreshold then
                CreateStorm(x, y, z)
            elseif convergenceStrength > hailThreshold then
                CreateHail(x,y,z)
            elseif convergenceStrength > rainThreshold then
                CreateRain(x,y,z)
            elseif convergenceStrength > cloudThreshold then
                CreateCloud(x, y, z)
            end
        end
    end
   
end



-- Llamar a SimulateClouds() para simular la formación y movimiento de las nubes
function UpdateWeather()
    if GetConVar("gdisasters_heat_system"):GetInt() >= 1 then
        if CLIENT then return end
        if CurTime() > nextUpdateWeather then
            nextUpdateWeather = CurTime() + updateInterval
            for x, column in pairs(GridMap) do
                for y, row in pairs(column) do
                    for z, cell in pairs(row) do
                        
                        UpdateCloudDensity(x,y,z)

                        SimulateConvergence(x, y, z)
                        -- Check for storm formation
                        CheckStormFormation(x, y, z)
                        -- Check for hail formation
                        CheckHailFormation(x, y, z)

                        
                    end
                end
            end
        end
    end
end

-- Función para generar la cuadrícula y actualizar la temperatura en cada ciclo
function GenerateGrid(ply)
    -- Obtener los límites del mapa
    local mapBounds = getMapBounds()
    local minX, minY, maxZ = math.floor(mapBounds[2].x / gridSize) * gridSize, math.floor(mapBounds[2].y / gridSize) * gridSize, math.ceil(mapBounds[2].z / gridSize) * gridSize
    local maxX, maxY, minZ = math.ceil(mapBounds[1].x / gridSize) * gridSize, math.ceil(mapBounds[1].y / gridSize) * gridSize, math.floor(mapBounds[1].z / gridSize) * gridSize

    print("Generating grid...") -- Depuración

    -- Inicializar la cuadrícula
    for x = minX, maxX, gridSize do
        GridMap[x] = {}
        for y = minY, maxY, gridSize do
            GridMap[x][y] = {}
            for z = minZ, maxZ, gridSize do
                GridMap[x][y][z] = {}
                GridMap[x][y][z].temperature = GLOBAL_SYSTEM_ORIGINAL["Atmosphere"]["Temperature"]
                GridMap[x][y][z].humidity = GLOBAL_SYSTEM_ORIGINAL["Atmosphere"]["Humidity"]
                GridMap[x][y][z].pressure = GLOBAL_SYSTEM_ORIGINAL["Atmosphere"]["Pressure"]
                GridMap[x][y][z].Airflow = GLOBAL_SYSTEM_ORIGINAL["Atmosphere"]["Wind"]["Speed"]
                GridMap[x][y][z].Airflow_Direction = GLOBAL_SYSTEM_ORIGINAL["Atmosphere"]["Wind"]["Direction"]
            end
        end
    end

    print("Grid generated.") -- Depuración

end

function UpdateGrid()
    if GetConVar("gdisasters_heat_system"):GetInt() >= 1 then
        if CurTime() > nextUpdateGrid then
            nextUpdateGrid = CurTime() + updateInterval

            for i= 1, updateBatchSize do
                local cell = table.remove(cellsToUpdate, 1)
                if not cell then
                    -- Reiniciar la lista de celdas para actualizar
                    cellsToUpdate = {}
                    for x, column in pairs(GridMap) do
                        for y, row in pairs(column) do
                            for z, cell in pairs(row) do
                                table.insert(cellsToUpdate, {x, y, z})
                            end
                        end
                    end
                    cell = table.remove(cellsToUpdate, 1)
                end

                if cell then
                    local x, y, z = cell[1], cell[2], cell[3]
                    if GridMap[x] and GridMap[x][y] and GridMap[x][y][z] then
                        local newTemperature = CalculateTemperature(x, y, z)
                        local newHumidity = CalculateHumidity(x, y, z)
                        local newPressure = CalculatePressure(x, y, z)
                        local newAirFlow = CalculateAirFlow(x, y, z)
                        local newAirFlowDirection = CalculateAirFlowDirection(x, y, z)
                        GridMap[x][y][z].temperature = newTemperature
                        GridMap[x][y][z].humidity = newHumidity
                        GridMap[x][y][z].pressure = newPressure
                        GridMap[x][y][z].Airflow = newAirFlow
                        GridMap[x][y][z].Airflow_Direction = newAirFlowDirection
                    else
                        print("Error: Cell position out of grid bounds.")
                    end
                end
            end
        end
    end
end
function UpdatePlayerGrid()
    if GetConVar("gdisasters_heat_system"):GetInt() >= 1 then
        if CurTime() > nextUpdateGridPlayer then
            nextUpdateGridPlayer = CurTime() + updateInterval

            for k,ply in pairs(player.GetAll()) do
                local pos = ply:GetPos()
                local px, py, pz = math.floor(pos.x / gridSize) * gridSize, math.floor(pos.y / gridSize) * gridSize, math.floor(pos.z / gridSize) * gridSize
                
                -- Comprueba si la posición calculada está dentro de los límites de la cuadrícula
                if GridMap[px] and GridMap[px][py] and GridMap[px][py][pz] then
                    local cell = GridMap[px][py][pz]

                    -- Verifica si las propiedades de la celda son válidas
                    if cell.temperature and cell.humidity and cell.pressure then
                        -- Actualiza las variables de la atmósfera del jugador
                        GLOBAL_SYSTEM_TARGET["Atmosphere"]["Temperature"] = cell.temperature
                        GLOBAL_SYSTEM_TARGET["Atmosphere"]["Humidity"] = cell.humidity
                        GLOBAL_SYSTEM_TARGET["Atmosphere"]["Pressure"] = cell.pressure
                        GLOBAL_SYSTEM_TARGET["Atmosphere"]["Wind"]["Speed"] = cell.Airflow
                        GLOBAL_SYSTEM_TARGET["Atmosphere"]["Wind"]["Direction"] = cell.Airflow_Direction
                        print("Actual grid: x: " .. px .. ", y: ".. py .. ", z: " .. pz .. ", Terrain Type: " .. cell.terrainType .. ", Temp: " .. cell.temperature .. ", Humidity: " .. cell.humidity .. ", Pressure: " .. cell.pressure .. ", Arflow Speed: " .. cell.Airflow )
                    else
                        -- Manejo de valores no válidos
                        print("Error: Valores no válidos en la celda de la cuadrícula.")
                    end
                else
                    -- Manejo de celdas fuera de los límites de la cuadrícula
                    print("Error: Posición fuera de los límites de la cuadrícula.")
                end
            end
        end
    end
end

function TemperatureToColor(temperature)
    -- Define una función simple para convertir la temperatura en un color
    local r = math.Clamp(temperature / 100, 0, 1)
    local b = math.Clamp(1 - r, 0, 1)
    return Color(r * 255, 0, b * 255)
end

function DrawGridDebug()
    if GetConVar("gdisasters_graphics_draw_heatsystem_grid"):GetInt() >= 1 then 
        local playerPos = LocalPlayer():GetPos()
        
        -- Verificar existencia de GridMap y maxDrawDistance
        if not GridMap then
            print("GridMap is not defined.")
            return
        end
        
        -- Verificar existencia de maxDrawDistance y gridSize
        if not maxDrawDistance or not gridSize then
            print("maxDrawDistance or gridSize is not defined.")
            return
        end

        for x, column in pairs(GridMap) do
            for y, row in pairs(column) do
                for z, cell in pairs(row) do
                    local cellpos = Vector(x, y, z)
                    if cell then
                        local temperature = cell.temperature or 0
                        local color = TemperatureToColor(temperature) or Color(255, 255, 255)  -- Asegúrate de que siempre haya un color

                        render.SetColorMaterial()
                        render.DrawBox(cellpos, Angle(0, 0, 0), Vector(-gridSize / 2, -gridSize / 2, -gridSize / 2), Vector(gridSize / 2, gridSize / 2, gridSize / 2), color)
                    else
                        -- Mensaje de depuración para celdas nulas
                        print("Cell at ", cellpos, " is nil.")
                    end
                end
            end
        end
    end
end

hook.Add("InitPostEntity", "gDisasters_GenerateGrid", GenerateGrid)
hook.Add("InitPostEntity", "gDisasters_AddTemperatureHumiditySources", AddTemperatureHumiditySources)
hook.Add("Think", "gDisasters_UpdateGrid", UpdateGrid)
hook.Add("Think", "gDisasters_UpdatePlayerGrid", UpdatePlayerGrid)
hook.Add("Think", "gDisasters_UpdateWeather", UpdateWeather)
hook.Add("PostDrawTranslucentRenderables", "gDisasters_DrawGridDebug", DrawGridDebug)