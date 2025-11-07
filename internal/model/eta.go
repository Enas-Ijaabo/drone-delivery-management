package model

import "math"

const (
	earthRadiusKm      = 6371.0
	droneSpeedMPS      = 10.0
	metersPerKilometer = 1000.0
)

type ETA int

func CalculateETA(drone *Drone, order *Order) ETA {
	if drone == nil {
		return 0
	}

	var distanceKm float64

	if order.Status == OrderPending || order.Status == OrderReserved {
		droneToPickup := haversineDistance(drone.Lat, drone.Lng, order.PickupLat, order.PickupLng)
		pickupToDropoff := haversineDistance(order.PickupLat, order.PickupLng, order.DropoffLat, order.DropoffLng)
		distanceKm = droneToPickup + pickupToDropoff
	} else {
		distanceKm = haversineDistance(drone.Lat, drone.Lng, order.DropoffLat, order.DropoffLng)
	}

	distanceMeters := distanceKm * metersPerKilometer

	timeSeconds := distanceMeters / droneSpeedMPS
	timeMinutes := timeSeconds / 60.0

	eta := int(math.Ceil(timeMinutes))
	if eta < 1 {
		eta = 1
	}

	return ETA(eta)
}

/*
haversineDistance: calculates the great-circle distance between two points
given their latitude and longitude in decimal degrees
Returns distance in kilometers
*/
func haversineDistance(lat1, lng1, lat2, lng2 float64) float64 {
	lat1Rad := lat1 * math.Pi / 180
	lat2Rad := lat2 * math.Pi / 180
	deltaLat := (lat2 - lat1) * math.Pi / 180
	deltaLng := (lng2 - lng1) * math.Pi / 180

	a := math.Sin(deltaLat/2)*math.Sin(deltaLat/2) +
		math.Cos(lat1Rad)*math.Cos(lat2Rad)*
			math.Sin(deltaLng/2)*math.Sin(deltaLng/2)

	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	return earthRadiusKm * c
}
