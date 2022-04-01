{# Snowflake specific implementation to create a primary key #}
{%- macro snowflake__create_primary_key(table_relation, column_names, quote_columns=false) -%}
    {%- set constraint_name = (table_relation.identifier ~ "_" ~ column_names|sort|join('_') ~ "_PK") | upper -%}
    {%- set columns_csv = dbt_constraints.get_quoted_column_csv(column_names, quote_columns) -%}

    {#- Check that the table does not already have this PK/UK -#} 
    {%- if not dbt_constraints.snowflake__unique_constraint_exists(table_relation, column_names) -%}

        {%- set query -%}
        ALTER TABLE {{table_relation}} ADD CONSTRAINT {{constraint_name}} PRIMARY KEY ( {{columns_csv}} ) RELY
        {%- endset -%}
        {%- do log("Creating primary key: " ~ constraint_name, info=true) -%}
        {%- do run_query(query) -%}

    {%- else -%}            
        {%- do log("Skipping " ~ constraint_name ~ " because PK/UK already exists: " ~ table_relation ~ " " ~ column_names, info=false) -%}
    {%- endif -%}

{%- endmacro -%}




{# Snowflake specific implementation to create a unique key #}
{%- macro snowflake__create_unique_key(table_relation, column_names, quote_columns=false) -%}
    {%- set constraint_name = (table_relation.identifier ~ "_" ~ column_names|sort|join('_') ~ "_UK") | upper -%}
    {%- set columns_csv = dbt_constraints.get_quoted_column_csv(column_names, quote_columns) -%}

    {#- Check that the table does not already have this PK/UK -#} 
    {%- if not dbt_constraints.snowflake__unique_constraint_exists(table_relation, column_names) -%}

        {%- set query -%}
        ALTER TABLE {{table_relation}} ADD CONSTRAINT {{constraint_name}} UNIQUE ( {{columns_csv}} ) RELY
        {%- endset -%}
        {%- do log("Creating unique key: " ~ constraint_name, info=true) -%}
        {%- do run_query(query) -%}

    {%- else -%}            
        {%- do log("Skipping " ~ constraint_name ~ " because PK/UK already exists: " ~ table_relation ~ " " ~ column_names, info=false) -%}
    {%- endif -%}

{%- endmacro -%}



{# Snowflake specific implementation to create a foreign key #}
{%- macro snowflake__create_foreign_key(test_model, pk_table_relation, pk_column_names, fk_table_relation, fk_column_names, quote_columns=true) -%}
    {%- set constraint_name = (fk_table_relation.identifier ~ "_" ~ fk_column_names|sort|join('_') ~ "_FK") | upper -%}
    {%- set fk_columns_csv = dbt_constraints.get_quoted_column_csv(fk_column_names, quote_columns) -%}
    {%- set pk_columns_csv = dbt_constraints.get_quoted_column_csv(pk_column_names, quote_columns) -%}
    {#- Check that the PK table has a PK or UK -#}
    {%- if dbt_constraints.snowflake__unique_constraint_exists(pk_table_relation, pk_column_names) -%}
        {#- Check if the table already has this foreign key -#} 
        {%- if not dbt_constraints.snowflake__foreign_key_exists(fk_table_relation, fk_column_names) -%}

            {%- set query -%}
            ALTER TABLE {{fk_table_relation}} ADD CONSTRAINT {{constraint_name}} FOREIGN KEY ( {{fk_columns_csv}} ) REFERENCES {{pk_table_relation}} ( {{pk_columns_csv}} ) RELY
            {%- endset -%}
            {%- do log("Creating foreign key: " ~ constraint_name, info=true) -%}
            {%- do run_query(query) -%}

        {%- else -%}            
            {%- do log("Skipping " ~ constraint_name ~ " because FK already exists: " ~ fk_table_relation ~ " " ~ fk_column_names, info=false) -%}
        {%- endif -%}
    {%- else -%} 
        {%- do log("Skipping " ~ constraint_name ~ " because a PK/UK was not found on the PK table: " ~ pk_table_relation ~ " " ~ pk_column_names, info=true) -%}
    {%- endif -%}

{%- endmacro -%}



{# This macro allows us to compare two sets of columns to see if they are the same, ignoring case #}
{%- macro snowflake__column_list_matches(listA, listB) -%}
    {# Test if A is empty or the lists are not the same size #}
    {%- if listA | count > 0 and listA | count == listB | count  -%}
        {# Fail if there are any columns in A that are not in B #}
        {%- for valueFromA in listA|map('upper') -%}
            {%- if valueFromA|upper not in listB| map('upper')  -%}
                {{ return(false) }}
            {%- endif -%}
        {% endfor %}
        {# Since we know the count is the same, A must equal B #}
        {{ return(true) }}
    {%- else -%}
        {{ return(false) }}
    {%- endif -%}
{%- endmacro -%}



{#- This macro is used in create macros to avoid duplicate PK/UK constraints 
    and to skip FK where no PK/UK constraint exists on the parent table -#}
{%- macro snowflake__unique_constraint_exists(table_relation, column_names) -%}
    {%- set lookup_query -%}
    SHOW UNIQUE KEYS IN TABLE {{table_relation}};
    {%- endset -%}
    {%- do log("Lookup: " ~ lookup_query, info=false) -%}
    {%- set constraint_list = run_query(lookup_query) -%}
    {%- if constraint_list.columns["column_name"].values() | count > 0 -%}
        {%- for constraint in constraint_list.group_by("constraint_name") -%}
            {%- if dbt_constraints.snowflake__column_list_matches(constraint.columns["column_name"].values(), column_names ) -%}
                {%- do log("Found UK key: " ~ table_relation ~ " " ~ column_names, info=false) -%}
                {{ return(true) }}
            {%- endif -%}
        {% endfor %}
    {%- endif -%}#}
    
    {%- set lookup_query -%}
    SHOW PRIMARY KEYS IN TABLE {{table_relation}};
    {%- endset -%}
    {%- do log("Lookup: " ~ lookup_query, info=false) -%}
    {%- set constraint_list = run_query(lookup_query) -%}
    {%- if constraint_list.columns["column_name"].values() | count > 0 -%}
        {%- for constraint in constraint_list.group_by("constraint_name") -%}
            {%- if dbt_constraints.snowflake__column_list_matches(constraint.columns["column_name"].values(), column_names ) -%}
                {%- do log("Found PK key: " ~ table_relation ~ " " ~ column_names, info=false) -%}
                {{ return(true) }}
            {%- endif -%}
        {% endfor %}
    {%- endif -%}

    {#- If we get this far then the table does not have either constraint -#}
    {%- do log("No PK/UK key: " ~ table_relation ~ " " ~ column_names, info=false) -%}
    {{ return(false) }}
{%- endmacro -%}



{#- This macro is used in create macros to avoid duplicate FK constraints -#}
{%- macro snowflake__foreign_key_exists(table_relation, column_names) -%}
    {%- set lookup_query -%}
    SHOW IMPORTED KEYS IN TABLE {{table_relation}};
    {%- endset -%}
    {%- do log("Lookup: " ~ lookup_query, info=false) -%}
    {%- set constraint_list = run_query(lookup_query) -%}
    {%- if constraint_list.columns["fk_column_name"].values() | count > 0 -%}
        {%- for constraint in constraint_list.group_by("fk_name") -%}
            {%- if dbt_constraints.snowflake__column_list_matches(constraint.columns["fk_column_name"].values(), column_names ) -%}
                {%- do log("Found FK key: " ~ table_relation ~ " " ~ column_names, info=false) -%}
                {{ return(true) }}
            {%- endif -%}
        {% endfor %}
    {%- endif -%}

    {#- If we get this far then the table does not have this constraint -#}
    {%- do log("No FK key: " ~ table_relation ~ " " ~ column_names, info=false) -%}
    {{ return(false) }}
{%- endmacro -%}