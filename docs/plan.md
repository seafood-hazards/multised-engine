# Plan for the developing a database to analyze pristine sediment.

## A pilot study

We have used five different sources and created databases. We have also developed five corresponding web sites as follows.

  - Mareano   : https://seafood-hazards.github.io/mareano-pilot/
  - Vannmiljø : https://seafood-hazards.github.io/vannmiljo-pilot/
  - ICES-DOME : https://seafood-hazards.github.io/ices-dome-pilot/
  - MUDAB     : https://seafood-hazards.github.io/mudab-pilot/
  - 4Demon    : https://seafood-hazards.github.io/4demon-pilot/

At the end of the pilot study, we generated the slim version of databases, which share a common schema. They are not exactly the same, but each DB contains the same tables with very similar format.

## Slim version

Based on the slim version of databases, we have perfomed several quality control procedures to make the clean versions of databases. During the clearning processes using the slim verson, we woule like to add several flagging columns to the slim verion. In addition, we would like to analyze the grain sizes at this stage. 

At the end of the processess, we would like to delete unnessary rows for our study to make the clean version of databases. 

Instead of making 5 websites, we would like to create a single website to summarize all data cleaning results.

## Clearn version

Based on the clean version of databases, we need to perfome several data wrangling steps.

 1. Use the common units
 2. Analyze normalization with iron and aluminium
 3. Analyze grain size distributions

At the end of the processess, we would like to craate a single database containing all five resources.

## Merged version

Based on the single database, we would like to perform different analyses to define background and pristine sediment data.

## Refined version

Based on the merged database, we cut a mart holding only what the background and pristine work needs: the seven target elements, the normalisers as a separate table, the baked ratios, and the links to aquaculture sites and repeat-sampled sites. The analyses on it define the background level per element and fraction, and classify each measurement as pristine or not.

## Summary layer

The refined site reports those analyses in full, for a reader who works with the data. On top of it we would like a short site that states what the work found in plain English, per element, for a reader who will not open the analysis sites.

This is not a sixth database. It is one analysis module that assembles the numbers the refined analyses already wrote, plus the site that draws them, so that the plain-English answer can never disagree with the analysis it summarises. No number is typed into a page: a number the site needs that no CSV holds is added to the module instead.
