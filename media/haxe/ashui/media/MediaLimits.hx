package ashui.media;

/** Bounds both native input and output queues. Defaults: 8 items, 16 MiB. **/
typedef MediaLimits = {
	?maxItems:Int,
	?maxBytes:Int
}
