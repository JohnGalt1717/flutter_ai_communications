# Known-profile registry evidence

JSON source of truth: `packages/flutter_ai_communications_shared/lib/src/data/known_profiles.json`.

Rows are advertised-name tokens plus whether that hardware suppresses capture noise. Bare OEM lists (Honda, Kia, Mazda, …) are omitted until a documented Bluetooth/audio name exists.

## Headsets

| id | Advertised tokens | Hardware noise processing | Evidence |
| --- | --- | --- | --- |
| airpods-pro | AirPods Pro | yes | [Apple compare](https://www.apple.com/airpods/compare/) |
| airpods-max | AirPods Max | yes | [Apple compare](https://www.apple.com/airpods/compare/) |
| airpods | AirPods (non-Pro) | no | [Apple compare](https://www.apple.com/airpods/compare/) |
| sony-wh-1000x | WH-1000XMn | yes | [Sony WH-1000XM5 specs](https://www.sony.com/electronics/support/wireless-headphones-bluetooth-headphones/wh-1000xm5/specifications) |
| bose-quietcomfort | QuietComfort / QC45 | yes | [Bose QC45 intro](https://www.bose.com/pressroom/bose-introduces-quietcomfort-45) |
| jabra-evolve2-anc | Evolve2 50/55/75/85 | yes | [PCMag Evolve2 75](https://www.pcmag.com/reviews/jabra-evolve2-75) |
| jabra-evolve2-65 | Evolve2 65 | no (passive only) | [Jabra Evolve2 65](https://www.amazon.com/Jabra-Bluetooth-Wireless-Headphones-Noise-Cancelling/dp/B0GHFLJQB3) |
| pixel-buds-pro | Pixel Buds Pro / 2a | yes | [Google I/O 2022](https://blog.google/products-and-platforms/devices/pixel/pixel-buds-pro-io-2022/) |

## Speakers

JBL Flip 6 pairing UI lists **JBL Flip 6**. No capture ANC. Jabra Speak is a far-field speakerphone.

## Cars

Cabin mics do not get a headset Baseline. Hardware noise processing is false; family is car (seed 5).

| id | Advertised tokens | Evidence |
| --- | --- | --- |
| tesla-model | Tesla Model 3/Y/S/X | [Tesla Motors Club: phone shows `Tesla Model 3 (name)`](https://teslamotorsclub.com/tmc/threads/bluetooth-goes-in-and-out-2-different-names-for-the-car-showing.327927/) |
| ford-sync | SYNC, Ford Focus | [Ford: search for "Ford Focus" or "SYNC"](https://www.ford.ie/support/how-tos/sync/getting-started-with-sync/how-to-pair-a-phone-with-sync) |
| uconnect | Uconnect | [Mopar: select Uconnect](https://www.mopar.com/en-us/technology/smartphone-pairing.html) |
| carplay | CarPlay | [Apple forums: `name = CarPlay`](https://developer.apple.com/forums/thread/732202) |
| rivian-audio | Rivian Audio | [Rivian: iPhone Bluetooth row "Rivian Audio"](https://rivian.com/support/article/rivian-assistant) |
| mb-bluetooth | MB Bluetooth | [COMAND pairing lists MB Bluetooth](https://www.mercedesmedic.com/pair-android-iphone-bluetooth-phone-with-mercedes-benz/) |
| bmw-identity | BMW | [BMW How-To: "the BMW identity will now appear on your phone"](https://www.youtube.com/watch?v=dx8e9X4ktlg) |
| lucid-head-unit | Lucid | [Lucid-XXXX Bluetooth output](https://lucidowners.com/threads/a-better-workaround-for-carplay-audio-choosing-the-wrong-source.8868/) |

Tesla phone-as-key BLE (`Tesla` + last six VIN digits) is not an audio Endpoint and is not in this table.
