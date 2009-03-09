/* log-desc.cxx
 *
 * COPYRIGHT (c) 2009 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 */

#include "log-desc.hxx"
#include <string.h>
#include <stack>

inline char *CopyString (const char *s)
{
    if (s == 0) return 0;
    return strcpy (new char[strlen(s)+1], s);
}

/***** class EventOrGroup member functions *****/

EventOrGroup::EventOrGroup (const char *name, EventKind kind)
{
    this->_name = CopyString(name);
    this->_kind = kind;
}

EventOrGroup::~EventOrGroup ()
{
    delete this->_name;
}



/***** class EventGroup member functions *****/

EventGroup::EventGroup (const char *name, int n)
    : EventOrGroup (name, LOG_GROUP), _kids(n, (EventOrGroup *)0)
{
}

EventGroup::~EventGroup ()
{
    /* FIXME: delete the kids */
}

void EventGroup::Add (int i, EventOrGroup *item)
{
    this->_kids.at(i) = item;
    item->SetGroup (this);
}


/***** class EventDesc member functions *****/

EventDesc::EventDesc (const char *name, EventKind kind)
    : EventOrGroup (name, kind)
{
}

EventDesc::~EventDesc ()
{
    delete this->_name;
    if (this->_args != 0) delete this->_args;
}


/***** class LogFileDesc member functions *****/

LogFileDesc::LogFileDesc (EventGroup *root)
{
    this->_root = root;
    this->_events = 0;
}

LogFileDesc::~LogFileDesc ()
{
    delete this->_root;
    delete this->_events;
}

/* visitor walks of the event hierarchy */

struct StkNode {
    EventGroup	*grp;
    int		i;		// child index in the group

    StkNode (EventGroup *g) { this->grp = g; this->i = 0; }

    EventOrGroup *Next ()
    {
	if (this->i < grp->NumKids())
	    return grp->Kid(this->i++);
	else
	    return 0;
    }

};

typedef std::stack<StkNode> Stack_t;

//! \brief do a pre-order traversal of the event hierarchy, calling the visitor methods at each
//! node.
void LogFileDesc::PreOrderWalk (LogDescVisitor *visitor)
{
    Stack_t stk;

    visitor->VisitGroup (this->_root);
    stk.push (StkNode(this->_root));
    while (! stk.empty()) {
	EventOrGroup *p = stk.top().Next();
	if (p == 0) {
	    stk.pop();
	}
	else {
	    EventGroup *grp = dynamic_cast<EventGroup *>(p);
	    if (grp != 0) {
		visitor->VisitGroup (grp);
		stk.push (StkNode(grp));
   	    }
	    else
		visitor->VisitEvent (static_cast<EventDesc *>(p));
	}
    }

}

//! \brief do a post-order traversal of the event hierarchy, calling the visitor methods at each
//! node.
void LogFileDesc::PostOrderWalk (LogDescVisitor *visitor)
{
    Stack_t stk;

    stk.push (StkNode(this->_root));
    while (! stk.empty()) {
	EventOrGroup *p = stk.top().Next();
	if (p == 0) {
	    visitor->VisitGroup (stk.top().grp);
	    stk.pop();
	}
	else {
	    EventGroup *grp = dynamic_cast<EventGroup *>(p);
	    if (grp != 0) {
		visitor->VisitGroup (grp);
		stk.push (StkNode(grp));
   	    }
	    else
		visitor->VisitEvent (static_cast<EventDesc *>(p));
	}
    }

}