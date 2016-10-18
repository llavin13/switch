-- Core schema for SWITCH-PYOMO, meant for PostgreSQL with PostGIS
-- extensions.
-- Copyright 2015 The Switch Authors. All rights reserved.
-- Licensed under the Apache License, Version 2, which is in the LICENSE file.


-- SWITCH schema

CREATE SCHEMA switch;
COMMENT ON SCHEMA switch
  IS 'This schema contains core tables for use with SWITCH-pyomo.

All major "data blocks", such as projects, technologies, load zones, fuel prices, among others, are indexed by integer scenario ids. These are used in the scenarios_switch table to set up different SWITCH scenarios that you can run. A script called get_switch_input_tables.py reads those keys and constructs input tables according to the specified scenarios ids.';

-----------------------------
-- Timescales
-----------------------------



-----------------------------
-- Load zones
-----------------------------



-----------------------------
-- Load time series
-----------------------------


-----------------------------
-- Transmission
-----------------------------



-----------------------------
-- Energy Sources
-----------------------------

CREATE TABLE switch.energy_sources
(
  energy_source character varying(30) PRIMARY KEY,
  is_fuel boolean NOT NULL,
  co2_intensity double precision,
  upstream_co2_intensity double precision,
);
COMMENT ON TABLE switch.energy_sources
  IS 'Contains fuels and non-fuel energy sources such as Solar or Wind. Fuels should specify their CO2 intensities, and non-fuel energy sources should leave those columns empy.';

-----------------------------
-- Generation technologies
-----------------------------

CREATE TABLE switch.generation_technology
(
  gen_tech_id integer PRIMARY KEY,
  technology_name varchar(60) NOT NULL,
  max_age smallint NOT NULL,
  "variable" boolean NOT NULL,
  baseload boolean NOT NULL,
  flexible_baseload boolean NOT NULL,
  cogen boolean NOT NULL,
  energy_source character varying(30) NOT NULL REFERENCES switch.energy_sources (energy_source),
  variable_o_m double precision,
  scheduled_outage_rate double precision,
  forced_outage_rate double precision,
  min_build_capacity double precision,
  full_load_heat_rate double precision,
  unit_size double precision,
  ccs_capture_efficiency double precision,
  ccs_energy_load double precision,
  storage_efficiency double precision,
  store_to_release_ratio double precision,
  min_load_fraction double precision,
  startup_fuel double precision,
  startup_om double precision
);
COMMENT ON TABLE switch.generation_technology
  IS 'Specifies all generation technologies, and generic attributes (average outage rates, etc) that provide default descriptions of projects that build a given generation technology.';
COMMENT ON COLUMN switch.generation_technology."variable"
  IS 'Specifies whether a technology is a variable renewable resource such as wind or solar.';
COMMENT ON COLUMN switch.generation_technology.baseload
  IS 'Specifies whether a technology is a baseload plant that must be constantly operated at maximum capacity.';
COMMENT ON COLUMN switch.generation_technology.flexible_baseload
  IS 'Specifies whether a technology is a flexible baseload plant whose output cannot change between time points, but can change between time series.';
COMMENT ON COLUMN switch.generation_technology.cogen
  IS 'Specifies whether a technology is a cogeneration plant that provides both heat and electricity.';
COMMENT ON COLUMN switch.generation_technology.energy_source
  IS 'Specifies what energy source powers this technology.';
COMMENT ON COLUMN switch.generation_technology.variable_o_m
  IS 'Variable costs for Operations & Maintenance incurred by running a generator, specified in units of real dollars per MWh. This provides default values for each project of this technology type.';
COMMENT ON COLUMN switch.generation_technology.scheduled_outage_rate
  IS 'The fraction of the time this plant needs to be offline for scheduled maintenance, annually.';
COMMENT ON COLUMN switch.generation_technology.forced_outage_rate
  IS 'The fraction of the time this plant is expected to be offline unexpectedly for maintenance, annually.';
COMMENT ON COLUMN switch.generation_technology.min_build_capacity
  IS 'The smallest allowed build of this technology, in MW.';
COMMENT ON COLUMN switch.generation_technology.full_load_heat_rate
  IS 'Should be NULL for non-thermal plants. For thermal plants, the heat rate in units of Thermal Energy per MWh. Thermal energy can be specified either in MMBTU on MJ, as long as the units are used consistently across the entire database in fuel prices, emissions, etc.';
COMMENT ON COLUMN switch.generation_technology.unit_size
  IS 'The typical size of an individual generator of this technology. This optional parameter is used for modeling discrete builds and unit commitment.';
COMMENT ON COLUMN switch.generation_technology.ccs_capture_efficiency
  IS 'The fraction of CO2 captured from smokestacks. This should be NULL for non-CCS projects.';
COMMENT ON COLUMN switch.generation_technology.ccs_energy_load
  IS 'The fraction of a plants output needed to operate the CCS equipment. If a generator with a nameplate capacity of 1 MW consumes 0.3 MW to operate CCS equipment, this factor would be 0.3. This should be NULL for non-CCS projects.';
COMMENT ON COLUMN switch.generation_technology.storage_efficiency
  IS 'The round trip efficiency of a storage technology, expressed as a fraction of energy stored that can delivered to the grid. This should be NULL for non-storage projects.';
COMMENT ON COLUMN switch.generation_technology.store_to_release_ratio
  IS 'The maximum rate that energy can be stored, expressed as a ratio of discharge power capacity. If unspecified, this will default to 1 in the switch model. This should be NULL for non-storage projects.';
COMMENT ON COLUMN switch.generation_technology.min_load_fraction
  IS 'The minimum loading level of a generation technology as a fraction of committed capacity, used for unit commitment. This optional parameter will default to 0 in the switch model if left unspecified here.';
COMMENT ON COLUMN switch.generation_technology.startup_fuel
  IS 'The fuel requirements of starting up additional generation capacity expressed in units of Thermal Energy per MW. This optional parameter will default to 0 in the switch model if left unspecified here.';
COMMENT ON COLUMN switch.generation_technology.startup_om
  IS 'Variable costs for Operations & Maintenance incurred by starting up a generator, specified in units of real dollars per MW.';



CREATE TABLE switch.gen_tech_cost_scenarios
(
  gen_tech_cost_scenarios_id INTEGER PRIMARY KEY,
  gen_tech_cost_scenario_name VARCHAR(30),
  notes text
);
COMMENT ON TABLE switch.gen_tech_cost_scenarios
  IS 'Defines a set of cost trajectories for all generation technologies.'



CREATE TABLE switch.gen_tech_costs
(
  gen_tech_cost_scenarios_id INTEGER REFERENCES switch.gen_tech_cost_scenarios (gen_tech_cost_scenarios_id),
  technology_name character varying(50),
  technology_id integer REFERENCES switch.generation_technology (gen_tech_id),
  build_year INTEGER,
  capital_cost double precision NOT NULL,
  fixed_om double precision NOT NULL,
  PRIMARY KEY (gen_tech_cost_scenarios_id, technology_id, build_year)
);
COMMENT ON TABLE switch.gen_tech_costs
  IS 'Cost trajectories for generation technologies.';
COMMENT ON COLUMN switch.gen_tech_costs.build_year
  IS 'The year that construction would be completed.';
COMMENT ON COLUMN switch.gen_tech_costs.capital_cost
  IS 'The projected "overnight" capital cost of a given technology installed in a given year, expressed in real dollars per MW of installed capacity.';
COMMENT ON COLUMN switch.gen_tech_costs.fixed_om
  IS 'The projected fixed costs of operations and maintenance of a given technology installed in a given year, expressed in real dollars per MW of capacity.';
CREATE OR REPLACE FUNCTION switch.gen_tech_costs_tech_name() RETURNS TRIGGER AS 
$$
DECLARE
    matching_rows INTEGER;
BEGIN
    IF NEW.technology_name IS NULL AND NEW.technology_id IS NULL THEN
        RAISE EXCEPTION 'No technology specified for gen_tech_costs.';
    ELSIF NEW.technology_name IS NULL THEN
        NEW.technology_name := (SELECT technology_name FROM switch.generation_technology WHERE gen_tech_id = NEW.technology_id);
    ELSEIF NEW.technology_id IS NULL THEN
        matching_rows := (SELECT count(*) FROM switch.generation_technology WHERE technology_name = NEW.technology_name);
        IF matching_rows > 1 THEN
            RAISE EXCEPTION 'Cannot auto-fill technology id in gen_tech_costs; more than one technology named % are in generation_technology.', NEW.technology_name;
        ELSIF matching_rows < 1 THEN
            RAISE EXCEPTION 'Cannot auto-fill technology id in gen_tech_costs; no technologies named % are in generation_technology.', NEW.technology_name;
        ELSE
            NEW.technology_id := (SELECT gen_tech_id FROM switch.generation_technology WHERE technology_name = NEW.technology_name);
        END IF;
    END IF;        
   RETURN NEW;
END
$$ LANGUAGE 'plpgsql';
CREATE TRIGGER gen_tech_costs_tech_name BEFORE INSERT OR UPDATE ON switch.gen_tech_costs
    FOR EACH ROW EXECUTE PROCEDURE switch.gen_tech_costs_tech_name();


-----------------------------
-- Projects
-----------------------------

CREATE TABLE switch.projects
(
  project_id integer PRIMARY KEY,
  project_name varchar(40) NOT NULL,
  gen_tech_id integer NOT NULL REFERENCES generation_tech (gen_tech_id),
  load_zone_id integer NOT NULL,
  connect_cost_per_mw double precision NOT NULL,
  capacity_limit_mw double precision,
  variable_o_m double precision,
  forced_outage_rate double precision,
  scheduled_outage_rate double precision,
  full_load_heat_rate double precision,
  hydro_efficiency double precision,
);
COMMENT ON TABLE switch.projects
  IS 'Defines generation and/or storage projects. A project may denote individual generating units, a site that includes several generating units, or an aggregation of several different sites that can be dispatched together without regard for unit commitment considerations. The generation_tech tables describes generation technologies in abstract terms and provide default values, while this table describes individual generators. 

The columns without NOT NULL constraints are optional, and should only be populated if that field is relevant for a particular project, or if you want to override the generic values from the generation_tech tables.';
COMMENT ON COLUMN switch.projects.capacity_limit_mw 
  IS 'This column should only be populated for projects that have an upper limit on allowed capacity, like a wind farm that is limited by land area.';
COMMENT ON COLUMN switch.projects.full_load_heat_rate 
  IS 'This column should only be defined for thermal projects, and is specified in units of MMBTU/MWh. This overrides generic values defined in generation_tech tables.';
COMMENT ON COLUMN switch.projects.hydro_efficiency 
  IS 'This column is used by the Chile hydro extension.';



CREATE TABLE switch.project_specific_costs
(
  project_id integer NOT NULL REFERENCES switch.projects (project_id),
  build_year integer NOT NULL,
  fixed_o_m double precision,
  overnight_cost double precision,
  PRIMARY KEY (project_id, build_year)
);
COMMENT ON TABLE switch.project_specific_costs
  IS 'Overrides generic costs from generation_tech tables for individual projects. Variable operations & maintenance costs are specified in the projects table because they not allowed to change over time in order to make the model computationally simpler.';



CREATE TABLE switch.projects_existing_and_planned
(
  project_id integer NOT NULL REFERENCES switch.projects (project_id),
  build_year integer NOT NULL,
  capacity double precision,
  PRIMARY KEY (project_id, build_year)
);
COMMENT ON TABLE switch.projects_existing_and_planned
  IS 'Describes existing and planned projects according to the year they came online (build_year), and the capacity that was brought online in that year.';
COMMENT ON COLUMN switch.projects_existing_and_planned.capacity
  IS 'Nameplate capacity in MW.';



CREATE TABLE switch.projects_variable_capacity_factors
(
  project_id integer NOT NULL REFERENCES switch.projects (project_id),
  timestamp_utc timestamp without time zone NOT NULL,
  capacity_factor double precision,
  PRIMARY KEY (project_id, timestamp_utc)
);
COMMENT ON TABLE switch.projects_variable_capacity_factors
  IS 'This contains historical time series of hourly capacity factors for variable renewable generators (wind, solar, etc). Multiplying these hourly capacity factors by the installed capacity will produce the hourly power output. This table should store the historical data for one or more reference years. These values will be projected to future years when a scenario is exported to SWITCH-pyomo input files.';
COMMENT ON COLUMN switch.projects_variable_capacity_factors.timestamp_utc IS 'This timestamp should be recorded in UTC. For regions that only span one time zone, this is less important. This should never contain daylight savings time because a time series specified in daylight savings time will drop one hour per year.';



CREATE TABLE switch.project_scenarios
(
  project_scenario_id int PRIMARY KEY,
  project_scenario_name varchar(32),
  notes text
);
COMMENT ON TABLE switch.project_scenarios
  IS 'Defines which set of projects to include in a particular SWITCH optimization. Use this to enable/disable projects, aggregate projects for faster planning simulations without unit commitment, etc.';



CREATE TABLE switch.project_scenario_members
(
  projects_scenario_id integer REFERENCES switch.project_scenarios (project_scenario_id),
  project_id integer REFERENCES switch.projects (project_id),
  PRIMARY KEY (projects_scenario_id, project_id)
);
COMMENT ON TABLE switch.project_scenario_members
  IS 'Defines which projects to include in a particular scenario.';



-----------------------------
-- Policies
-----------------------------



