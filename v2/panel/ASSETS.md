# Ikonki Minecrafta

Panel używa lokalnych atlasów prawdziwych ikonek przedmiotów i stworzeń Minecrafta.
Źródła: pliki `Invicon_*` i `EntitySprite_*` z [Minecraft Wiki](https://minecraft.wiki/),
pobrane 2026-10-24 przez publiczne API MediaWiki. Każdy identyfikator katalogu
ma przypisaną ikonę: 1657 przedmiotów i 90 stworzeń. Wizualnie identyczne warianty
(np. woskowana miedź) korzystają z tego samego obrazu. Dla stworzeń z odmianami
wybrano domyślny wariant; pillager i vindicator mają wspólny portret illagera.

Minecraft oraz jego grafiki należą do Mojang Studios / Microsoft. Atlasy nie są
oryginalnymi grafikami NIK i nie są objęte licencją kodu projektu. Autorstwo
renderów i historia poszczególnych plików: strony `File:Invicon …` oraz
`File:EntitySprite …` w Minecraft Wiki. NIK jest nieoficjalnym projektem fanowskim,
nie jest produktem Mojang ani Microsoft i nie jest przez te firmy zatwierdzony.

PNG są zapakowane w dwa atlasy; CSS zawiera współrzędne, a `icons.json` jawne
powiązania identyfikatorów. Przeglądarka pobiera je z własnego serwera panelu.
Nie ma zewnętrznych żądań obrazków ani przekazywania nazw graczy do serwisów z grafiką.
Service worker przechowuje wyłącznie publiczne atlasy i indeks, bez danych graczy.

Jedenaście nowszych ikonek (włócznie, klucz próby, kwiat kaktusa i suche trawy)
pochodzi z oryginalnych tekstur Minecraft 26.1 udostępnionych w repozytorium
[PrismarineJS/minecraft-assets](https://github.com/PrismarineJS/minecraft-assets/tree/master/data/26.1).
Nazwy źródłowych plików dla każdego ID znajdują się w sekcji `sources` indeksu.
