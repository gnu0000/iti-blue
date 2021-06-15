rem bclient.exe put http://a:a@localhost:3000/Space3/place1/e multipart_related_sample_2.txt



bclient space_put           ./TestSpace
bclient place_put           ./TestSpace/TestPlace1
bclient place2_put          ./TestSpace/TestPlace2
bclient multipart_thing_put ./TestSpace/TestPlace1/foo multipart_related_sample_2.txt
bclient multipart_thing_put ./TestSpace/TestPlace2/foo multipart_related_sample_2.txt