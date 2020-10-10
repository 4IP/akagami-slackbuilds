/* volume.app.c */

/* Volume.app -- a simple volume control
 *
 * Copyright (C) 2000
 *	Daniel Richard G. <skunk@mit.edu>,
 *	timecop <timecop@japan.co.jp>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 */

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <signal.h>
#include <unistd.h>
#include <sys/stat.h>
#include <X11/X.h>
#include <X11/Xlib.h>

#include "common.h"
#include "knob.h"
#include "misc.h"
#include "mixer.h"

static int source = DEFAULT_SOURCE;
static char *mixer_device = NULL;
static bool list_sources = false;

static Display *display;
static int display_height;

static double prev_button1_press_time = 0.0;
static bool button1_pressed = false;
static int mouse_drag_home_x;
static int mouse_drag_home_y;

static void
signal_catch(int sig)
{
	switch (sig)
	{
		case SIGUSR1:
		knob_turn(-0.1);
		break;

		case SIGUSR2:
		knob_turn(0.1);
		break;

		default:
		abort();
		break;
	}

	signal(sig, signal_catch);
}

static void
button_press_event(XButtonEvent *event)
{
	double button_press_time = get_current_time();

	switch (event->button)
	{
		/* Left click
		 */
		case 1:
		knob_grab();
		if ((button_press_time - prev_button1_press_time) <= MAX_DOUBLE_CLICK_TIME)
		{
			/* Double-click
			 */
			knob_toggle_mute();
			prev_button1_press_time = 0.0;
		} else
		  system("amixer set Master unmute");
			prev_button1_press_time = button_press_time;
		button1_pressed = true;
		mouse_drag_home_x = event->x;
		mouse_drag_home_y = event->y;
		break;

		case 3:
		/*
		 * Right click
		 */

		/* popup menu? */

		break;

		case BUTTON_WHEEL_UP:
		knob_turn(0.05);
		break;

		case BUTTON_WHEEL_DOWN:
		knob_turn(-0.05);
		break;

		default:
                break;
	}
}

static void
button_release_event(XButtonEvent *event)
{
	if (event->button == 1)
	{
		knob_release();
		button1_pressed = false;
	}
}

static void
mouse_motion_event(XMotionEvent *event)
{
	if (button1_pressed)
	{
		if ((event->x == mouse_drag_home_x) && (event->y == mouse_drag_home_y))
		{
			/* This motion event was generated by an earlier
			 * XWarpPointer() call, so ignore it.
			 */
			return;
		}

		if (event->y != mouse_drag_home_y)
		{
			int delta_y = mouse_drag_home_y - event->y;
			float delta_volume = (float)delta_y / (float)display_height;
			knob_turn(delta_volume);
		}

		/* Keep mouse pointer on the knob. Note that this call
		 * will generate a bogus motion event (see above)
		 */
		XWarpPointer(
			display,
			None,
			event->window,
			event->x, event->y,
			0, 0,
			mouse_drag_home_x, mouse_drag_home_y);
	}
}

#define HELP_TEXT \
	"Volume.app " VERSION "\n" \
	"usage:\n" \
	"  -c <n>    source to control [1]\n" \
	"            (see -l option)\n" \
	"  -d <dev>  mixer device [" DEFAULT_MIXER_DEVICE "]\n" \
	"  -h        print this help\n" \
	"  -l        print list of available sound sources\n"

void
parse_cli_options(int argc, char **argv)
{
	int opt;

	while ((opt = getopt(argc, argv, "c:hl")) != EOF)
	{
		switch (opt)
		{
			case 'c':
			if (optarg != NULL)
				source = strtod(optarg, NULL) - 1;
			break;

			case 'd':
			if (optarg != NULL)
			{
				if (mixer_device != NULL)
					free(mixer_device);
				mixer_device = strdup(optarg);
			}
			break;

			case 'h':
			fputs(HELP_TEXT, stdout);
			exit(0);
			break;

			case 'l':
			list_sources = true;
			break;

			default:
			break;
		}
	}
}

int
main(int argc, char **argv)
{
	char *display_name;
	XEvent event;
	int idle_tick = 0;

#ifdef DEBUG
	fputs("**** Volume.app: debug build starting ****\n", stderr);
#endif

	parse_cli_options(argc, argv);

	display_name = getenv("DISPLAY");
	display = XOpenDisplay(display_name);
	if (display == NULL)
	{
		if (display_name == NULL)
			fputs("Unable to open display\n", stderr);
		else
			fprintf(stderr, "Unable to open display \"%s\"\n", display_name);
		return EXIT_FAILURE;
	}
	XFlush(display);

	display_height = (float)DisplayHeight(display, DefaultScreen(display));

	if (mixer_device == NULL)
		mixer_device = strdup(DEFAULT_MIXER_DEVICE);
	mixer_init(mixer_device);
	free(mixer_device);

	if (list_sources)
	{
		mixer_print_sources();
		return EXIT_SUCCESS;
	}

	if ((source < 0) || (source >= mixer_get_source_count()))
	{
		fprintf(stderr, "Invalid source number: %d\n", source + 1);
		return EXIT_FAILURE;
	}
	mixer_set_source(source);

	knob_init(display);
	knob_update();

	signal(SIGUSR1, signal_catch);
	signal(SIGUSR2, signal_catch);

	/* Main event loop
	 */
	while (true)
	{
		if (button1_pressed || (XPending(display) > 0))
		{
			XNextEvent(display, &event);

			switch (event.type)
			{
				case Expose:
				knob_redraw();
				break;

				case ButtonPress:
				button_press_event(&event.xbutton);
				idle_tick = 0;
				break;

				case ButtonRelease:
				button_release_event(&event.xbutton);
				idle_tick = 0;
				break;

				case MotionNotify:
				mouse_motion_event(&event.xmotion);
				idle_tick = 0;
				break;

				case DestroyNotify:
				XCloseDisplay(display);
				goto main_event_loop_exit;

				default:
				break;
			}
		} else {
			knob_update();
			usleep(100000);
			++idle_tick;
		}
	}
	main_event_loop_exit:

	return EXIT_SUCCESS;
}

/* end volume.app.c */