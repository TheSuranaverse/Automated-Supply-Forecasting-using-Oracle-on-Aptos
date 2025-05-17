module SupplyOracle::SupplyForecasting {
    use std::error;
    use std::signer;
    use aptos_framework::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_ALREADY_INITIALIZED: u64 = 2;
    const E_NOT_INITIALIZED: u64 = 3;
    const E_INVALID_FORECAST_DATA: u64 = 4;
    const E_ZERO_SUPPLY: u64 = 5;

    /// Struct to hold oracle data for supply forecasting
    struct OracleData has store, drop {
        product_id: u64,
        current_supply: u64,
        market_demand: u64,
        timestamp: u64,
    }

    /// Event emitted when a forecast is updated
    struct ForecastUpdateEvent has drop, store {
        product_id: u64,
        forecasted_supply: u64,
        timestamp: u64,
    }

    /// Main resource struct to store forecasting data
    struct SupplyForecastStore has key {
        oracle_data: OracleData,
        forecasted_supply: u64,
        last_update_time: u64,
        forecast_events: EventHandle<ForecastUpdateEvent>,
        owner: address,
    }

    /// Initialize the supply forecasting system for a product
    public entry fun initialize(
        account: &signer,
        product_id: u64,
        initial_supply: u64,
        initial_demand: u64
    ) {
        let owner_address = signer::address_of(account);
        
        // Make sure the store hasn't been initialized already
        assert!(!exists<SupplyForecastStore>(owner_address), error::already_exists(E_ALREADY_INITIALIZED));
        
        // Check for valid initial values
        assert!(initial_demand > 0, error::invalid_argument(E_INVALID_FORECAST_DATA));
        assert!(initial_supply > 0, error::invalid_argument(E_ZERO_SUPPLY));

        // Create initial oracle data
        let oracle_data = OracleData {
            product_id,
            current_supply: initial_supply,
            market_demand: initial_demand,
            timestamp: timestamp::now_seconds(),
        };
        
        // Create and move the store to the owner's account
        let store = SupplyForecastStore {
            oracle_data,
            forecasted_supply: 0, // Will be calculated in the first update
            last_update_time: timestamp::now_seconds(),
            forecast_events: event::new_event_handle<ForecastUpdateEvent>(account),
            owner: owner_address,
        };
        
        move_to(account, store);

        // Emit initial forecast event
        event::emit_event(&mut store.forecast_events, ForecastUpdateEvent {
            product_id,
            forecasted_supply: initial_supply,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update the oracle data and calculate a new supply forecast
    public entry fun update_forecast(
        account: &signer,
        owner_address: address,
        current_supply: u64,
        market_demand: u64
    ) acquires SupplyForecastStore {
        // Verify the store exists
        assert!(exists<SupplyForecastStore>(owner_address), error::not_found(E_NOT_INITIALIZED));
        
        let caller_address = signer::address_of(account);
        let store = borrow_global_mut<SupplyForecastStore>(owner_address);
        
        // Only the owner can update the forecast
        assert!(caller_address == store.owner, error::permission_denied(E_NOT_AUTHORIZED));
        
        // Ensure the data is valid (demand shouldn't be zero for calculation purposes)
        assert!(market_demand > 0, error::invalid_argument(E_INVALID_FORECAST_DATA));
        
        // Update oracle data
        store.oracle_data.current_supply = current_supply;
        store.oracle_data.market_demand = market_demand;
        store.oracle_data.timestamp = timestamp::now_seconds();
        
        // Simple forecasting algorithm:
        // If demand > supply, increase by 20% over current demand
        // If demand <= supply, reduce to 110% of current demand
        let new_forecast = if (market_demand > current_supply) {
            (market_demand * 120) / 100 // Increase by 20%
        } else {
            (market_demand * 110) / 100 // Keep 10% buffer above demand
        };
        
        // Update the forecast
        store.forecasted_supply = new_forecast;
        store.last_update_time = timestamp::now_seconds();
        
        // Emit an event with the new forecast data
        event::emit_event(&mut store.forecast_events, ForecastUpdateEvent {
            product_id: store.oracle_data.product_id,
            forecasted_supply: new_forecast,
            timestamp: timestamp::now_seconds(),
        });
    }
}