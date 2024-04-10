class Api::V1::FeaturesController < ApplicationController
  def index

    page = params[:page].to_i  || 1
    per_page = params[:per_page].to_i || 10
    mag_type = params[:mag_type] ? params[:mag_type].split(",") : null


    if mag_type && !(["md", "ml", "ms", "mw", "me", "mi", "mb", "mlg", "mwr", "mb_lg", "mww"] & mag_type).any?
      render json: {error: "no podemos filtrar por magtype, ya que no es válido"}

      return
    end

    if per_page > 1000 || per_page <= 0 || per_page.is_a?(String)
      render json: {error: "El feed per_page es un valor númerico superior a 0 y menor 1000"}

      return
    end

    if page.is_a?(String) || page <= 0
      render json: {error: "El feed page es un valor númerico positivo"}

      return
    end 


    init = Time.now
    total_features = mag_type&.length ? Feature.where(mag_type: mag_type).count : Feature.count

    if total_features.zero?
      if(mag_type.length && Feature.exists?)
         render json: {data: []}

         return
      end

      getData()
      total_features = mag_type&.length ? Feature.where(mag_type: mag_type).count : Feature.count
    end

    
    if mag_type&.length
      query_features = Feature.where(mag_type: mag_type).paginate(page: page, per_page: per_page)
        
    else
      query_features = Feature.paginate(page: page, per_page: page)  
    
    end

    features  = query_features
    .left_joins(:comments)
    .group("features.id")
     .map do |feature|
      {
       "id": feature["id"],
       "type": feature["type"],
       "attributes": {
         "external_id": feature["external_id"],
         "magnitude": feature["magnitude"],
         "place": feature["place"],
         "time": feature["time"],
         "tsunami": feature["tsunami"],
         "mag_type": feature["mag_type"],
         "title": feature["title"],
         "coordinates": {
           "longitude": feature["longitude"],
           "latitude": feature["latitude"]
           }
       },
       "links": {
         "external_url": feature["external_url"]
       },
       "comments": feature.comments
      }
    end
       
   fin = Time.now
   puts "TIEMPO GASTADO: #{fin-init}"

    response  = {
      data: features,
      pagination: {
        current_page: page,
        per_page: per_page,
        total: total_features
      }
    }

    render json: response
    # @features = Feature.all
    # return @features
  end

  def getData

    require 'httparty'

    response = HTTParty.get('https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_month.geojson')

    # @features, en esta variable almacenaré los datos que necesito de la respuesta a la usgs
    @features = []

    if response["metadata"]["status"] === 200
      
      response["features"].each do |feature|

        # Magnitud
        magnitude = feature["properties"]["mag"].to_f 
        # Latitud
        latitude = feature["geometry"]["coordinates"][0].to_f  
        # Longitud
        longitude = feature["geometry"]["coordinates"][1].to_f 
        # Magtype
        mag_type = feature["properties"]["magType"]
        #tilte
        title = feature["properties"]["title"]
        #place
        place = feature["properties"]["place"]
        #url 
        url = feature["properties"]["url"]
        
        # De acuerdo a la condiciones del reto solo obtengo aquellos features que cumplan con las condiciones.
        if (mag_type && latitude && longitude && magnitude && title && place && url && magnitude >= -1.0 && magnitude <= 10.0 && latitude >= -90.0 && latitude <= 90 && longitude >= -180.0 && longitude<= 180.0)
         puts mag_type if feature["id"] === 'us7000mb3r'
            data = {
                :type=>feature["type"],
                :external_id=>feature["id"],
                :magnitude=>magnitude,
                :place=> place,
                :time=>feature["properties"]["time"],
                :tsunami=>feature["properties"]["tsunami"] === 1,
                :mag_type=>mag_type,
                :title=>title,
                :longitude=>longitude,
                :latitude=>latitude,
                :external_url=>url
              }
            

              @features << data

          
        end
      end

      puts @features.length

      begin
        Feature.upsert_all(@features, unique_by: :external_id)
        # Feature.upsert_all(@features, unique_by: :external_id, returning: Arel.sql('id, external_id magnitude, place, time, tsunami, mag_type, title, longitude, latitude, external_url'))
      rescue ActiveRecord::RecordInvalid => e
        puts "Error al guardar registros: #{e}"
      end

    else
      puts "Error al obtener los datos: #{response.metadata?.status}"
    end

  
  end

end
