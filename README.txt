Creates a Semantic Data Collection Changefile for Solve for All based on HTML
documentation from Mozilla Developer Network.

ruby -d main.rb

should output html_tags.json.bz2 which can then be uploaded.

See https://solveforall.com/docs/developer/semantic_data_collection for more info.

TODO: remove images and fix links inside summary HTML.
