package dashboard;

/** The dock's pages. **/
enum Tab {
	Navigate;
	Media;
	Vehicle;
	Charging;
	Camera;
	Phone;
	Profile;
	More;
}

/** What the transmission is in. **/
enum Gear {
	P;
	R;
	N;
	D;
}

/** How the dashboard looks: the system's scheme, or one the driver chose. **/
enum Appearance {
	Auto;
	Light;
	Dark;
}
